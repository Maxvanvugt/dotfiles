#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'English'
require 'shellwords'
require 'erb'
require 'tempfile'
require 'net/http'
require 'json'

TEMPLATE = DATA.read
UNSETS = %w[
  FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS
  FZF_TMUX FZF_TMUX_OPTS
  FZF_CTRL_T_COMMAND FZF_CTRL_T_OPTS
  FZF_ALT_C_COMMAND
  FZF_ALT_C_OPTS FZF_CTRL_R_OPTS
  FZF_API_KEY
].freeze
DEFAULT_TIMEOUT = 10

FILE = File.expand_path(__FILE__)
BASE = File.expand_path('..', __dir__)
Dir.chdir(BASE)
FZF = "FZF_DEFAULT_OPTS=\"--no-scrollbar --pointer \\> --marker \\>\" FZF_DEFAULT_COMMAND= #{BASE}/bin/fzf"

def wait(timeout = DEFAULT_TIMEOUT)
  since = Time.now
  begin
    yield or raise Minitest::Assertion, 'Assertion failure'
  rescue Minitest::Assertion
    raise if Time.now - since > timeout

    sleep(0.05)
    retry
  end
end

class Shell
  class << self
    def bash
      @bash ||=
        begin
          bashrc = '/tmp/fzf.bash'
          File.open(bashrc, 'w') do |f|
            f.puts ERB.new(TEMPLATE).result(binding)
          end

          "bash --rcfile #{bashrc}"
        end
    end

    def zsh
      @zsh ||=
        begin
          zdotdir = '/tmp/fzf-zsh'
          FileUtils.rm_rf(zdotdir)
          FileUtils.mkdir_p(zdotdir)
          File.open("#{zdotdir}/.zshrc", 'w') do |f|
            f.puts ERB.new(TEMPLATE).result(binding)
          end
          "ZDOTDIR=#{zdotdir} zsh"
        end
    end

    def fish
      "unset #{UNSETS.join(' ')}; rm -f ~/.local/share/fish/fzf_test_history; FZF_DEFAULT_OPTS=\"--no-scrollbar --pointer '>' --marker '>'\" fish_history=fzf_test fish"
    end
  end
end

class Tmux
  attr_reader :win

  def initialize(shell = :bash)
    @win = go(%W[new-window -d -P -F #I #{Shell.send(shell)}]).first
    go(%W[set-window-option -t #{@win} pane-base-index 0])
    return unless shell == :fish

    send_keys 'function fish_prompt; end; clear', :Enter
    self.until(&:empty?)
  end

  def kill
    go(%W[kill-window -t #{win}])
  end

  def focus
    go(%W[select-window -t #{win}])
  end

  def send_keys(*args)
    go(%W[send-keys -t #{win}] + args.map(&:to_s))
  end

  def paste(str)
    system('tmux', 'setb', str, ';', 'pasteb', '-t', win, ';', 'send-keys', '-t', win, 'Enter')
  end

  def capture
    go(%W[capture-pane -p -J -t #{win}]).map(&:rstrip).reverse.drop_while(&:empty?).reverse
  end

  def until(refresh = false, timeout: DEFAULT_TIMEOUT)
    lines = nil
    begin
      wait(timeout) do
        lines = capture
        class << lines
          def counts
            lazy
              .map { |l| l.scan(%r{^. ([0-9]+)/([0-9]+)( \(([0-9]+)\))?}) }
              .reject(&:empty?)
              .first&.first&.map(&:to_i)&.values_at(0, 1, 3) || [0, 0, 0]
          end

          def match_count
            counts[0]
          end

          def item_count
            counts[1]
          end

          def select_count
            counts[2]
          end

          def any_include?(val)
            method = val.is_a?(Regexp) ? :match : :include?
            find { |line| line.send(method, val) }
          end
        end
        yield(lines).tap do |ok|
          send_keys 'C-l' if refresh && !ok
        end
      end
    rescue Minitest::Assertion
      puts $ERROR_INFO.backtrace
      puts '>' * 80
      puts lines
      puts '<' * 80
      raise
    end
    lines
  end

  def prepare
    tries = 0
    begin
      self.until(true) do |lines|
        message = "Prepare[#{tries}]"
        send_keys ' ', 'C-u', :Enter, message, :Left, :Right
        lines[-1] == message
      end
    rescue Minitest::Assertion
      (tries += 1) < 5 ? retry : raise
    end
    send_keys 'C-u', 'C-l'
  end

  private

  def go(args)
    IO.popen(%w[tmux] + args) { |io| io.readlines(chomp: true) }
  end
end

class TestBase < Minitest::Test
  TEMPNAME = Dir::Tmpname.create(%w[fzf]) {}
  FIFONAME = Dir::Tmpname.create(%w[fzf-fifo]) {}

  attr_reader :tmux

  def writelines(lines)
    File.write(TEMPNAME, lines.join("\n"))
  end

  def tempname
    TEMPNAME
  end

  def fzf_output
    @thread.join.value.chomp.tap { @thread = nil }
  end

  def fzf_output_lines
    fzf_output.lines(chomp: true)
  end

  def setup
    FileUtils.rm_f([TEMPNAME, FIFONAME])
    File.mkfifo(FIFONAME)
  end

  def teardown
    FileUtils.rm_f([TEMPNAME, FIFONAME])
  end

  alias assert_equal_org assert_equal
  def assert_equal(expected, actual)
    # Ignore info separator
    actual = actual&.sub(/\s*─+$/, '') if actual.is_a?(String) && actual&.match?(%r{\d+/\d+})
    assert_equal_org(expected, actual)
  end

  # Run fzf with its output piped to a fifo
  def fzf(*opts)
    raise 'fzf_output not taken' if @thread

    @thread = Thread.new { File.read(FIFONAME) }
    fzf!(*opts) + " > #{FIFONAME}"
  end

  def fzf!(*opts)
    opts = opts.map do |o|
      case o
      when Symbol
        o = o.to_s
        o.length > 1 ? "--#{o.tr('_', '-')}" : "-#{o}"
      when String, Numeric
        o.to_s
      end
    end.compact
    "#{FZF} #{opts.join(' ')}"
  end
end

class TestGoFZF < TestBase
  def setup
    super
    @tmux = Tmux.new
  end

  def teardown
    super
    @tmux.kill
  end

  def test_vanilla
    tmux.send_keys "seq 1 100000 | #{fzf}", :Enter
    tmux.until do |lines|
      assert_equal '>', lines.last
      assert_equal '  100000/100000', lines[-2]
    end
    lines = tmux.capture
    assert_equal '  2',             lines[-4]
    assert_equal '> 1',             lines[-3]
    assert_equal '  100000/100000', lines[-2]
    assert_equal '>',               lines[-1]

    # Testing basic key bindings
    tmux.send_keys '99', 'C-a', '1', 'C-f', '3', 'C-b', 'C-h', 'C-u', 'C-e', 'C-y', 'C-k', 'Tab', 'BTab'
    tmux.until do |lines|
      assert_equal '> 3910', lines[-4]
      assert_equal '  391', lines[-3]
      assert_equal '  856/100000', lines[-2]
      assert_equal '> 391', lines[-1]
    end

    tmux.send_keys :Enter
    assert_equal '3910', fzf_output
  end

  def test_fzf_default_command
    tmux.send_keys fzf.sub('FZF_DEFAULT_COMMAND=', "FZF_DEFAULT_COMMAND='echo hello'"), :Enter
    tmux.until { |lines| assert_equal '> hello', lines[-3] }

    tmux.send_keys :Enter
    assert_equal 'hello', fzf_output
  end

  def test_fzf_default_command_failure
    tmux.send_keys fzf.sub('FZF_DEFAULT_COMMAND=', 'FZF_DEFAULT_COMMAND=false'), :Enter
    tmux.until { |lines| assert_includes lines[-2], '  [Command failed: false] ─' }
    tmux.send_keys :Enter
  end

  def test_key_bindings
    tmux.send_keys "#{FZF} -q 'foo bar foo-bar'", :Enter
    tmux.until { |lines| assert_equal '> foo bar foo-bar', lines.last }

    # CTRL-A
    tmux.send_keys 'C-A', '('
    tmux.until { |lines| assert_equal '> (foo bar foo-bar', lines.last }

    # META-F
    tmux.send_keys :Escape, :f, ')'
    tmux.until { |lines| assert_equal '> (foo) bar foo-bar', lines.last }

    # CTRL-B
    tmux.send_keys 'C-B', 'var'
    tmux.until { |lines| assert_equal '> (foovar) bar foo-bar', lines.last }

    # Left, CTRL-D
    tmux.send_keys :Left, :Left, 'C-D'
    tmux.until { |lines| assert_equal '> (foovr) bar foo-bar', lines.last }

    # META-BS
    tmux.send_keys :Escape, :BSpace
    tmux.until { |lines| assert_equal '> (r) bar foo-bar', lines.last }

    # CTRL-Y
    tmux.send_keys 'C-Y', 'C-Y'
    tmux.until { |lines| assert_equal '> (foovfoovr) bar foo-bar', lines.last }

    # META-B
    tmux.send_keys :Escape, :b, :Space, :Space
    tmux.until { |lines| assert_equal '> (  foovfoovr) bar foo-bar', lines.last }

    # CTRL-F / Right
    tmux.send_keys 'C-F', :Right, '/'
    tmux.until { |lines| assert_equal '> (  fo/ovfoovr) bar foo-bar', lines.last }

    # CTRL-H / BS
    tmux.send_keys 'C-H', :BSpace
    tmux.until { |lines| assert_equal '> (  fovfoovr) bar foo-bar', lines.last }

    # CTRL-E
    tmux.send_keys 'C-E', 'baz'
    tmux.until { |lines| assert_equal '> (  fovfoovr) bar foo-barbaz', lines.last }

    # CTRL-U
    tmux.send_keys 'C-U'
    tmux.until { |lines| assert_equal '>', lines.last }

    # CTRL-Y
    tmux.send_keys 'C-Y'
    tmux.until { |lines| assert_equal '> (  fovfoovr) bar foo-barbaz', lines.last }

    # CTRL-W
    tmux.send_keys 'C-W', 'bar-foo'
    tmux.until { |lines| assert_equal '> (  fovfoovr) bar bar-foo', lines.last }

    # META-D
    tmux.send_keys :Escape, :b, :Escape, :b, :Escape, :d, 'C-A', 'C-Y'
    tmux.until { |lines| assert_equal '> bar(  fovfoovr) bar -foo', lines.last }

    # CTRL-M
    tmux.send_keys 'C-M'
    tmux.until { |lines| refute_equal '>', lines.last }
  end

  def test_file_word
    tmux.send_keys "#{FZF} -q '--/foo bar/foo-bar/baz' --filepath-word", :Enter
    tmux.until { |lines| assert_equal '> --/foo bar/foo-bar/baz', lines.last }

    tmux.send_keys :Escape, :b
    tmux.send_keys :Escape, :b
    tmux.send_keys :Escape, :b
    tmux.send_keys :Escape, :d
    tmux.send_keys :Escape, :f
    tmux.send_keys :Escape, :BSpace
    tmux.until { |lines| assert_equal '> --///baz', lines.last }
  end

  def test_multi_order
    tmux.send_keys "seq 1 10 | #{fzf(:multi)}", :Enter
    tmux.until { |lines| assert_equal '>', lines.last }

    tmux.send_keys :Tab, :Up, :Up, :Tab, :Tab, :Tab, # 3, 2
                   'C-K', 'C-K', 'C-K', 'C-K', :BTab, :BTab, # 5, 6
                   :PgUp, 'C-J', :Down, :Tab, :Tab # 8, 7
    tmux.until { |lines| assert_equal '  10/10 (6)', lines[-2] }
    tmux.send_keys 'C-M'
    assert_equal %w[3 2 5 6 8 7], fzf_output_lines
  end

  def test_multi_max
    tmux.send_keys "seq 1 10 | #{FZF} -m 3 --bind A:select-all,T:toggle-all --preview 'echo [{+}]/{}'", :Enter

    tmux.until { |lines| assert_equal 10, lines.item_count }

    tmux.send_keys '1'
    tmux.until do |lines|
      assert_includes lines[1], ' [1]/1 '
      assert lines[-2]&.start_with?('  2/10 ')
    end

    tmux.send_keys 'A'
    tmux.until do |lines|
      assert_includes lines[1], ' [1 10]/1 '
      assert lines[-2]&.start_with?('  2/10 (2/3)')
    end

    tmux.send_keys :BSpace
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (2/3)') }

    tmux.send_keys 'T'
    tmux.until do |lines|
      assert_includes lines[1], ' [2 3 4]/1 '
      assert lines[-2]&.start_with?('  10/10 (3/3)')
    end

    %w[T A].each do |key|
      tmux.send_keys key
      tmux.until do |lines|
        assert_includes lines[1], ' [1 5 6]/1 '
        assert lines[-2]&.start_with?('  10/10 (3/3)')
      end
    end

    tmux.send_keys :BTab
    tmux.until do |lines|
      assert_includes lines[1], ' [5 6]/2 '
      assert lines[-2]&.start_with?('  10/10 (2/3)')
    end

    [:BTab, :BTab, 'A'].each do |key|
      tmux.send_keys key
      tmux.until do |lines|
        assert_includes lines[1], ' [5 6 2]/3 '
        assert lines[-2]&.start_with?('  10/10 (3/3)')
      end
    end

    tmux.send_keys '2'
    tmux.until { |lines| assert lines[-2]&.start_with?('  1/10 (3/3)') }

    tmux.send_keys 'T'
    tmux.until do |lines|
      assert_includes lines[1], ' [5 6]/2 '
      assert lines[-2]&.start_with?('  1/10 (2/3)')
    end

    tmux.send_keys :BSpace
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (2/3)') }

    tmux.send_keys 'A'
    tmux.until do |lines|
      assert_includes lines[1], ' [5 6 1]/1 '
      assert lines[-2]&.start_with?('  10/10 (3/3)')
    end
  end

  def test_multi_action
    tmux.send_keys "seq 10 | #{FZF} --bind 'a:change-multi,b:change-multi(3),c:change-multi(xxx),d:change-multi(0)'", :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 ') }
    tmux.send_keys 'a'
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (0)') }
    tmux.send_keys 'b'
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (0/3)') }
    tmux.send_keys :BTab
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (1/3)') }
    tmux.send_keys 'c'
    tmux.send_keys :BTab
    tmux.until { |lines| assert lines[-2]&.start_with?('  10/10 (2/3)') }
    tmux.send_keys 'd'
    tmux.until do |lines|
      assert lines[-2]&.start_with?('  10/10 ') && !lines[-2]&.include?('(')
    end
  end

  def test_with_nth
    [true, false].each do |multi|
      tmux.send_keys "(echo '  1st 2nd 3rd/';
                       echo '  first second third/') |
                       #{fzf(multi && :multi, :x, :nth, 2, :with_nth, '2,-1,1')}",
                     :Enter
      tmux.until { |lines| assert_equal multi ? '  2/2 (0)' : '  2/2', lines[-2] }

      # Transformed list
      lines = tmux.capture
      assert_equal '  second third/first', lines[-4]
      assert_equal '> 2nd 3rd/1st',        lines[-3]

      # However, the output must not be transformed
      if multi
        tmux.send_keys :BTab, :BTab
        tmux.until { |lines| assert_equal '  2/2 (2)', lines[-2] }
        tmux.send_keys :Enter
        assert_equal ['  1st 2nd 3rd/', '  first second third/'], fzf_output_lines
      else
        tmux.send_keys '^', '3'
        tmux.until { |lines| assert_equal '  1/2', lines[-2] }
        tmux.send_keys :Enter
        assert_equal ['  1st 2nd 3rd/'], fzf_output_lines
      end
    end
  end

  def test_scroll
    [true, false].each do |rev|
      tmux.send_keys "seq 1 100 | #{fzf(rev && :reverse)}", :Enter
      tmux.until { |lines| assert_equal '  100/100', lines[rev ? 1 : -2] }
      tmux.send_keys(*Array.new(110) { rev ? :Down : :Up })
      tmux.until { |lines| assert_includes lines, '> 100' }
      tmux.send_keys :Enter
      assert_equal '100', fzf_output
    end
  end

  def test_select_1
    tmux.send_keys "seq 1 100 | #{fzf(:with_nth, '..,..', :print_query, :q, 5555, :'1')}", :Enter
    assert_equal %w[5555 55], fzf_output_lines
  end

  def test_exit_0
    tmux.send_keys "seq 1 100 | #{fzf(:with_nth, '..,..', :print_query, :q, 555_555, :'0')}", :Enter
    assert_equal %w[555555], fzf_output_lines
  end

  def test_select_1_exit_0_fail
    [:'0', :'1', %i[1 0]].each do |opt|
      tmux.send_keys "seq 1 100 | #{fzf(:print_query, :multi, :q, 5, *opt)}", :Enter
      tmux.until { |lines| assert_equal '> 5', lines.last }
      tmux.send_keys :BTab, :BTab, :BTab
      tmux.until { |lines| assert_equal '  19/100 (3)', lines[-2] }
      tmux.send_keys :Enter
      assert_equal %w[5 5 50 51], fzf_output_lines
    end
  end

  def test_query_unicode
    tmux.paste "(echo abc; echo $'\\352\\260\\200\\353\\202\\230\\353\\213\\244') | #{fzf(:query, "$'\\352\\260\\200\\353\\213\\244'")}"
    tmux.until { |lines| assert_equal '  1/2', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[가나다], fzf_output_lines
  end

  def test_sync
    tmux.send_keys "seq 1 100 | #{FZF} --multi | awk '{print $1 $1}' | #{fzf(:sync)}", :Enter
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys 9
    tmux.until { |lines| assert_equal '  19/100 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  19/100 (3)', lines[-2] }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys 'C-K', :Enter
    assert_equal %w[9090], fzf_output_lines
  end

  def test_tac
    tmux.send_keys "seq 1 1000 | #{fzf(:tac, :multi)}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  1000/1000 (3)', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[1000 999 998], fzf_output_lines
  end

  def test_tac_sort
    tmux.send_keys "seq 1 1000 | #{fzf(:tac, :multi)}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys '99'
    tmux.until { |lines| assert_equal '  28/1000 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  28/1000 (3)', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[99 999 998], fzf_output_lines
  end

  def test_tac_nosort
    tmux.send_keys "seq 1 1000 | #{fzf(:tac, :no_sort, :multi)}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys '00'
    tmux.until { |lines| assert_equal '  10/1000 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  10/1000 (3)', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[1000 900 800], fzf_output_lines
  end

  def test_expect
    test = lambda do |key, feed, expected = key|
      tmux.send_keys "seq 1 100 | #{fzf(:expect, key, :prompt, "[#{key}]")}", :Enter
      tmux.until { |lines| assert_equal '  100/100', lines[-2] }
      tmux.send_keys '55'
      tmux.until { |lines| assert_equal '  1/100', lines[-2] }
      tmux.send_keys(*feed)
      tmux.prepare
      assert_equal [expected, '55'], fzf_output_lines
    end
    test.call('ctrl-t', 'C-T')
    test.call('ctrl-t', 'Enter', '')
    test.call('alt-c', %i[Escape c])
    test.call('f1', 'f1')
    test.call('f2', 'f2')
    test.call('f3', 'f3')
    test.call('f2,f4', 'f2', 'f2')
    test.call('f2,f4', 'f4', 'f4')
    test.call('alt-/', %i[Escape /])
    %w[f5 f6 f7 f8 f9 f10].each do |key|
      test.call('f5,f6,f7,f8,f9,f10', key, key)
    end
    test.call('@', '@')
  end

  def test_expect_with_bound_actions
    tmux.send_keys "seq 1 100 | #{fzf('--query 1 --print-query --expect z --bind z:up+up')}", :Enter
    tmux.until { |lines| assert_equal 20, lines.match_count }
    tmux.send_keys('z')
    assert_equal %w[1 z 1], fzf_output_lines
  end

  def test_expect_print_query
    tmux.send_keys "seq 1 100 | #{fzf('--expect=alt-z', :print_query)}", :Enter
    tmux.until { |lines| assert_equal '  100/100', lines[-2] }
    tmux.send_keys '55'
    tmux.until { |lines| assert_equal '  1/100', lines[-2] }
    tmux.send_keys :Escape, :z
    assert_equal %w[55 alt-z 55], fzf_output_lines
  end

  def test_expect_printable_character_print_query
    tmux.send_keys "seq 1 100 | #{fzf('--expect=z --print-query')}", :Enter
    tmux.until { |lines| assert_equal '  100/100', lines[-2] }
    tmux.send_keys '55'
    tmux.until { |lines| assert_equal '  1/100', lines[-2] }
    tmux.send_keys 'z'
    assert_equal %w[55 z 55], fzf_output_lines
  end

  def test_expect_print_query_select_1
    tmux.send_keys "seq 1 100 | #{fzf('-q55 -1 --expect=alt-z --print-query')}", :Enter
    assert_equal ['55', '', '55'], fzf_output_lines
  end

  def test_toggle_sort
    ['--toggle-sort=ctrl-r', '--bind=ctrl-r:toggle-sort'].each do |opt|
      tmux.send_keys "seq 1 111 | #{fzf("-m +s --tac #{opt} -q11")}", :Enter
      tmux.until { |lines| assert_equal '> 111', lines[-3] }
      tmux.send_keys :Tab
      tmux.until { |lines| assert_equal '  4/111 -S (1)', lines[-2] }
      tmux.send_keys 'C-R'
      tmux.until { |lines| assert_equal '> 11', lines[-3] }
      tmux.send_keys :Tab
      tmux.until { |lines| assert_equal '  4/111 +S (2)', lines[-2] }
      tmux.send_keys :Enter
      assert_equal %w[111 11], fzf_output_lines
    end
  end

  def test_unicode_case
    writelines(%w[строКА1 СТРОКА2 строка3 Строка4])
    assert_equal %w[СТРОКА2 Строка4], `#{FZF} -fС < #{tempname}`.lines(chomp: true)
    assert_equal %w[строКА1 СТРОКА2 строка3 Строка4], `#{FZF} -fс < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak
    input = %w[
      --foobar--------
      -----foobar---
      ----foobar--
      -------foobar-
    ]
    writelines(input)

    assert_equal input, `#{FZF} -ffoobar --tiebreak=index < #{tempname}`.lines(chomp: true)

    by_length = %w[
      ----foobar--
      -----foobar---
      -------foobar-
      --foobar--------
    ]
    assert_equal by_length, `#{FZF} -ffoobar < #{tempname}`.lines(chomp: true)
    assert_equal by_length, `#{FZF} -ffoobar --tiebreak=length < #{tempname}`.lines(chomp: true)

    by_begin = %w[
      --foobar--------
      ----foobar--
      -----foobar---
      -------foobar-
    ]
    assert_equal by_begin, `#{FZF} -ffoobar --tiebreak=begin < #{tempname}`.lines(chomp: true)
    assert_equal by_begin, `#{FZF} -f"!z foobar" -x --tiebreak begin < #{tempname}`.lines(chomp: true)

    assert_equal %w[
      -------foobar-
      ----foobar--
      -----foobar---
      --foobar--------
    ], `#{FZF} -ffoobar --tiebreak end < #{tempname}`.lines(chomp: true)

    assert_equal input, `#{FZF} -f"!z" -x --tiebreak end < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak_index_begin
    writelines([
                 'xoxxxxxoxx',
                 'xoxxxxxox',
                 'xxoxxxoxx',
                 'xxxoxoxxx',
                 'xxxxoxox',
                 '  xxoxoxxx'
               ])

    assert_equal [
      'xxxxoxox',
      '  xxoxoxxx',
      'xxxoxoxxx',
      'xxoxxxoxx',
      'xoxxxxxox',
      'xoxxxxxoxx'
    ], `#{FZF} -foo < #{tempname}`.lines(chomp: true)

    assert_equal [
      'xxxoxoxxx',
      'xxxxoxox',
      '  xxoxoxxx',
      'xxoxxxoxx',
      'xoxxxxxoxx',
      'xoxxxxxox'
    ], `#{FZF} -foo --tiebreak=index < #{tempname}`.lines(chomp: true)

    # Note that --tiebreak=begin is now based on the first occurrence of the
    # first character on the pattern
    assert_equal [
      '  xxoxoxxx',
      'xxxoxoxxx',
      'xxxxoxox',
      'xxoxxxoxx',
      'xoxxxxxoxx',
      'xoxxxxxox'
    ], `#{FZF} -foo --tiebreak=begin < #{tempname}`.lines(chomp: true)

    assert_equal [
      '  xxoxoxxx',
      'xxxoxoxxx',
      'xxxxoxox',
      'xxoxxxoxx',
      'xoxxxxxox',
      'xoxxxxxoxx'
    ], `#{FZF} -foo --tiebreak=begin,length < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak_begin_algo_v2
    writelines(['baz foo bar',
                'foo bar baz'])
    assert_equal [
      'foo bar baz',
      'baz foo bar'
    ], `#{FZF} -fbar --tiebreak=begin --algo=v2 < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak_end
    writelines(['xoxxxxxxxx',
                'xxoxxxxxxx',
                'xxxoxxxxxx',
                'xxxxoxxxx',
                'xxxxxoxxx',
                '  xxxxoxxx'])

    assert_equal [
      '  xxxxoxxx',
      'xxxxoxxxx',
      'xxxxxoxxx',
      'xoxxxxxxxx',
      'xxoxxxxxxx',
      'xxxoxxxxxx'
    ], `#{FZF} -fo < #{tempname}`.lines(chomp: true)

    assert_equal [
      'xxxxxoxxx',
      '  xxxxoxxx',
      'xxxxoxxxx',
      'xxxoxxxxxx',
      'xxoxxxxxxx',
      'xoxxxxxxxx'
    ], `#{FZF} -fo --tiebreak=end < #{tempname}`.lines(chomp: true)

    assert_equal [
      'xxxxxoxxx',
      '  xxxxoxxx',
      'xxxxoxxxx',
      'xxxoxxxxxx',
      'xxoxxxxxxx',
      'xoxxxxxxxx'
    ], `#{FZF} -fo --tiebreak=end,length,begin < #{tempname}`.lines(chomp: true)

    writelines(['/bar/baz', '/foo/bar/baz'])
    assert_equal [
      '/foo/bar/baz',
      '/bar/baz'
    ], `#{FZF} -fbaz --tiebreak=end < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak_length_with_nth
    input = %w[
      1:hell
      123:hello
      12345:he
      1234567:h
    ]
    writelines(input)

    output = %w[
      1:hell
      12345:he
      123:hello
      1234567:h
    ]
    assert_equal output, `#{FZF} -fh < #{tempname}`.lines(chomp: true)

    # Since 0.16.8, --nth doesn't affect --tiebreak
    assert_equal output, `#{FZF} -fh -n2 -d: < #{tempname}`.lines(chomp: true)
  end

  def test_tiebreak_chunk
    writelines(['1 foobarbaz ba',
                '2 foobar baz',
                '3 foo barbaz'])

    assert_equal [
      '3 foo barbaz',
      '2 foobar baz',
      '1 foobarbaz ba'
    ], `#{FZF} -fo --tiebreak=chunk < #{tempname}`.lines(chomp: true)

    assert_equal [
      '1 foobarbaz ba',
      '2 foobar baz',
      '3 foo barbaz'
    ], `#{FZF} -fba --tiebreak=chunk < #{tempname}`.lines(chomp: true)

    assert_equal [
      '3 foo barbaz'
    ], `#{FZF} -f'!foobar' --tiebreak=chunk < #{tempname}`.lines(chomp: true)
  end

  def test_invalid_cache
    tmux.send_keys "(echo d; echo D; echo x) | #{fzf('-q d')}", :Enter
    tmux.until { |lines| assert_equal '  2/3', lines[-2] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '  3/3', lines[-2] }
    tmux.send_keys :D
    tmux.until { |lines| assert_equal '  1/3', lines[-2] }
    tmux.send_keys :Enter
  end

  def test_invalid_cache_query_type
    command = %[(echo 'foo$bar'; echo 'barfoo'; echo 'foo^bar'; echo "foo'1-2"; seq 100) | #{FZF}]

    # Suffix match
    tmux.send_keys command, :Enter
    tmux.until { |lines| assert_equal 104, lines.match_count }
    tmux.send_keys 'foo$'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys 'bar'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter

    # Prefix match
    tmux.prepare
    tmux.send_keys command, :Enter
    tmux.until { |lines| assert_equal 104, lines.match_count }
    tmux.send_keys '^bar'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys 'C-a', 'foo'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter

    # Exact match
    tmux.prepare
    tmux.send_keys command, :Enter
    tmux.until { |lines| assert_equal 104, lines.match_count }
    tmux.send_keys "'12"
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys 'C-a', 'foo'
    tmux.until { |lines| assert_equal 1, lines.match_count }
  end

  def test_smart_case_for_each_term
    assert_equal 1, `echo Foo bar | #{FZF} -x -f "foo Fbar" | wc -l`.to_i
  end

  def test_bind
    tmux.send_keys "seq 1 1000 | #{fzf('-m --bind=ctrl-j:accept,u:up,T:toggle-up,t:toggle')}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys 'uuu', 'TTT', 'tt', 'uu', 'ttt', 'C-j'
    assert_equal %w[4 5 6 9], fzf_output_lines
  end

  def test_bind_print_query
    tmux.send_keys "seq 1 1000 | #{fzf('-m --bind=ctrl-j:print-query')}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys 'print-my-query', 'C-j'
    assert_equal %w[print-my-query], fzf_output_lines
  end

  def test_bind_replace_query
    tmux.send_keys "seq 1 1000 | #{fzf('--print-query --bind=ctrl-j:replace-query')}", :Enter
    tmux.send_keys '1'
    tmux.until { |lines| assert_equal '  272/1000', lines[-2] }
    tmux.send_keys 'C-k', 'C-j'
    tmux.until { |lines| assert_equal '  29/1000', lines[-2] }
    tmux.until { |lines| assert_equal '> 10', lines[-1] }
  end

  def test_long_line
    data = '.' * 256 * 1024
    File.open(tempname, 'w') do |f|
      f << data
    end
    assert_equal data, `#{FZF} -f . < #{tempname}`.chomp
  end

  def test_read0
    lines = `find .`.lines(chomp: true)
    assert_equal lines.last, `find . | #{FZF} -e -f "^#{lines.last}$"`.chomp
    assert_equal \
      lines.last,
      `find . -print0 | #{FZF} --read0 -e -f "^#{lines.last}$"`.chomp
  end

  def test_select_all_deselect_all_toggle_all
    tmux.send_keys "seq 100 | #{fzf('--bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --multi')}", :Enter
    tmux.until { |lines| assert_equal '  100/100 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  100/100 (3)', lines[-2] }
    tmux.send_keys 'C-t'
    tmux.until { |lines| assert_equal '  100/100 (97)', lines[-2] }
    tmux.send_keys 'C-a'
    tmux.until { |lines| assert_equal '  100/100 (100)', lines[-2] }
    tmux.send_keys :Tab, :Tab
    tmux.until { |lines| assert_equal '  100/100 (98)', lines[-2] }
    tmux.send_keys '100'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys 'C-d'
    tmux.until { |lines| assert_equal '  1/100 (97)', lines[-2] }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.send_keys 'C-d'
    tmux.until { |lines| assert_equal '  100/100 (0)', lines[-2] }
    tmux.send_keys :BTab, :BTab
    tmux.until { |lines| assert_equal '  100/100 (2)', lines[-2] }
    tmux.send_keys 0
    tmux.until { |lines| assert_equal '  10/100 (2)', lines[-2] }
    tmux.send_keys 'C-a'
    tmux.until { |lines| assert_equal '  10/100 (12)', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[1 2 10 20 30 40 50 60 70 80 90 100],
                 fzf_output_lines
  end

  def test_history
    history_file = '/tmp/fzf-test-history'

    # History with limited number of entries
    FileUtils.rm_f(history_file)
    opts = "--history=#{history_file} --history-size=4"
    input = %w[00 11 22 33 44]
    input.each do |keys|
      tmux.prepare
      tmux.send_keys "seq 100 | #{FZF} #{opts}", :Enter
      tmux.until { |lines| assert_equal '  100/100', lines[-2] }
      tmux.send_keys keys
      tmux.until { |lines| assert_equal '  1/100', lines[-2] }
      tmux.send_keys :Enter
    end
    wait do
      assert_path_exists history_file
      assert_equal input[1..], File.readlines(history_file, chomp: true)
    end

    # Update history entries (not changed on disk)
    tmux.send_keys "seq 100 | #{FZF} #{opts}", :Enter
    tmux.until { |lines| assert_equal '  100/100', lines[-2] }
    tmux.send_keys 'C-p'
    tmux.until { |lines| assert_equal '> 44', lines[-1] }
    tmux.send_keys 'C-p'
    tmux.until { |lines| assert_equal '> 33', lines[-1] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '> 3', lines[-1] }
    tmux.send_keys 1
    tmux.until { |lines| assert_equal '> 31', lines[-1] }
    tmux.send_keys 'C-p'
    tmux.until { |lines| assert_equal '> 22', lines[-1] }
    tmux.send_keys 'C-n'
    tmux.until { |lines| assert_equal '> 31', lines[-1] }
    tmux.send_keys 0
    tmux.until { |lines| assert_equal '> 310', lines[-1] }
    tmux.send_keys :Enter
    wait do
      assert_path_exists history_file
      assert_equal %w[22 33 44 310], File.readlines(history_file, chomp: true)
    end

    # Respect --bind option
    tmux.send_keys "seq 100 | #{FZF} #{opts} --bind ctrl-p:next-history,ctrl-n:previous-history", :Enter
    tmux.until { |lines| assert_equal '  100/100', lines[-2] }
    tmux.send_keys 'C-n', 'C-n', 'C-n', 'C-n', 'C-p'
    tmux.until { |lines| assert_equal '> 33', lines[-1] }
    tmux.send_keys :Enter
  ensure
    FileUtils.rm_f(history_file)
  end

  def test_execute
    output = '/tmp/fzf-test-execute'
    opts = %[--bind "alt-a:execute(echo /{}/ >> #{output})+change-header(alt-a),alt-b:execute[echo /{}{}/ >> #{output}]+change-header(alt-b),C:execute(echo /{}{}{}/ >> #{output})+change-header(C)"]
    writelines(%w[foo'bar foo"bar foo$bar])
    tmux.send_keys "cat #{tempname} | #{FZF} #{opts}", :Enter
    tmux.until { |lines| assert_equal 3, lines.item_count }

    ready = ->(s) { tmux.until { |lines| assert_includes lines[-3], s } }
    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    tmux.send_keys :Escape, :b
    ready.call('alt-b')

    tmux.send_keys :Up
    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    tmux.send_keys :Escape, :b
    ready.call('alt-b')

    tmux.send_keys :Up
    tmux.send_keys :C
    ready.call('C')

    tmux.send_keys 'barfoo'
    tmux.until { |lines| assert_equal '  0/3', lines[-2] }

    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    tmux.send_keys :Escape, :b
    ready.call('alt-b')

    wait do
      assert_path_exists output
      assert_equal %w[
        /foo'bar/ /foo'barfoo'bar/
        /foo"bar/ /foo"barfoo"bar/
        /foo$barfoo$barfoo$bar/
      ], File.readlines(output, chomp: true)
    end
  ensure
    FileUtils.rm_f(output)
  end

  def test_execute_multi
    output = '/tmp/fzf-test-execute-multi'
    opts = %[--multi --bind "alt-a:execute-multi(echo {}/{+} >> #{output})+change-header(alt-a),alt-b:change-header(alt-b)"]
    writelines(%w[foo'bar foo"bar foo$bar foobar])
    tmux.send_keys "cat #{tempname} | #{FZF} #{opts}", :Enter
    ready = ->(s) { tmux.until { |lines| assert_includes lines[-3], s } }

    tmux.until { |lines| assert_equal '  4/4 (0)', lines[-2] }
    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    tmux.send_keys :Escape, :b
    ready.call('alt-b')

    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal '  4/4 (3)', lines[-2] }
    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    tmux.send_keys :Escape, :b
    ready.call('alt-b')

    tmux.send_keys :Tab, :Tab
    tmux.until { |lines| assert_equal '  4/4 (3)', lines[-2] }
    tmux.send_keys :Escape, :a
    ready.call('alt-a')
    wait do
      assert_path_exists output
      assert_equal [
        %(foo'bar/foo'bar),
        %(foo'bar foo"bar foo$bar/foo'bar foo"bar foo$bar),
        %(foo'bar foo"bar foobar/foo'bar foo"bar foobar)
      ], File.readlines(output, chomp: true)
    end
  ensure
    FileUtils.rm_f(output)
  end

  def test_execute_plus_flag
    output = tempname + '.tmp'
    FileUtils.rm_f(output)
    writelines(['foo bar', '123 456'])

    tmux.send_keys "cat #{tempname} | #{FZF} --multi --bind 'x:execute-silent(echo {+}/{}/{+2}/{2} >> #{output})'", :Enter

    tmux.until { |lines| assert_equal '  2/2 (0)', lines[-2] }
    tmux.send_keys 'xy'
    tmux.until { |lines| assert_equal '  0/2 (0)', lines[-2] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '  2/2 (0)', lines[-2] }

    tmux.send_keys :Up
    tmux.send_keys :Tab
    tmux.send_keys 'xy'
    tmux.until { |lines| assert_equal '  0/2 (1)', lines[-2] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '  2/2 (1)', lines[-2] }

    tmux.send_keys :Tab
    tmux.send_keys 'xy'
    tmux.until { |lines| assert_equal '  0/2 (2)', lines[-2] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '  2/2 (2)', lines[-2] }

    wait do
      assert_path_exists output
      assert_equal [
        %(foo bar/foo bar/bar/bar),
        %(123 456/foo bar/456/bar),
        %(123 456 foo bar/foo bar/456 bar/bar)
      ], File.readlines(output, chomp: true)
    end
  rescue StandardError
    FileUtils.rm_f(output)
  end

  def test_execute_shell
    # Custom script to use as $SHELL
    output = tempname + '.out'
    FileUtils.rm_f(output)
    writelines(['#!/usr/bin/env bash', "echo $1 / $2 > #{output}"])
    system("chmod +x #{tempname}")

    tmux.send_keys "echo foo | SHELL=#{tempname} fzf --bind 'enter:execute:{}bar'", :Enter
    tmux.until { |lines| assert_equal '  1/1', lines[-2] }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal '  1/1', lines[-2] }
    wait do
      assert_path_exists output
      assert_equal ["-c / 'foo'bar"], File.readlines(output, chomp: true)
    end
  ensure
    FileUtils.rm_f(output)
  end

  def test_cycle
    tmux.send_keys "seq 8 | #{FZF} --cycle", :Enter
    tmux.until { |lines| assert_equal '  8/8', lines[-2] }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal '> 8', lines[-10] }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal '> 7', lines[-9] }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal '> 8', lines[-10] }
    tmux.send_keys :PgUp
    tmux.until { |lines| assert_equal '> 8', lines[-10] }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal '> 1', lines[-3] }
    tmux.send_keys :PgDn
    tmux.until { |lines| assert_equal '> 1', lines[-3] }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal '> 8', lines[-10] }
  end

  def test_header_lines
    tmux.send_keys "seq 100 | #{fzf('--header-lines=10 -q 5')}", :Enter
    2.times do
      tmux.until do |lines|
        assert_equal '  18/90', lines[-2]
        assert_equal '  1', lines[-3]
        assert_equal '  2', lines[-4]
        assert_equal '> 50', lines[-13]
      end
      tmux.send_keys :Down
    end
    tmux.send_keys :Enter
    assert_equal '50', fzf_output
  end

  def test_header_lines_reverse
    tmux.send_keys "seq 100 | #{fzf('--header-lines=10 -q 5 --reverse')}", :Enter
    2.times do
      tmux.until do |lines|
        assert_equal '  18/90', lines[1]
        assert_equal '  1', lines[2]
        assert_equal '  2', lines[3]
        assert_equal '> 50', lines[12]
      end
      tmux.send_keys :Up
    end
    tmux.send_keys :Enter
    assert_equal '50', fzf_output
  end

  def test_header_lines_reverse_list
    tmux.send_keys "seq 100 | #{fzf('--header-lines=10 -q 5 --layout=reverse-list')}", :Enter
    2.times do
      tmux.until do |lines|
        assert_equal '> 50', lines[0]
        assert_equal '  2', lines[-4]
        assert_equal '  1', lines[-3]
        assert_equal '  18/90', lines[-2]
      end
      tmux.send_keys :Up
    end
    tmux.send_keys :Enter
    assert_equal '50', fzf_output
  end

  def test_header_lines_overflow
    tmux.send_keys "seq 100 | #{fzf('--header-lines=200')}", :Enter
    tmux.until do |lines|
      assert_equal '  0/0', lines[-2]
      assert_equal '  1', lines[-3]
    end
    tmux.send_keys :Enter
    assert_equal '', fzf_output
  end

  def test_header_lines_with_nth
    tmux.send_keys "seq 100 | #{fzf('--header-lines 5 --with-nth 1,1,1,1,1')}", :Enter
    tmux.until do |lines|
      assert_equal '  95/95', lines[-2]
      assert_equal '  11111', lines[-3]
      assert_equal '  55555', lines[-7]
      assert_equal '> 66666', lines[-8]
    end
    tmux.send_keys :Enter
    assert_equal '6', fzf_output
  end

  def test_header
    tmux.send_keys %[seq 100 | #{FZF} --header "$(head -5 #{FILE})"], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  100/100', lines[-2]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[-7..-3]
      assert_equal '> 1', lines[-8]
    end
  end

  def test_header_reverse
    tmux.send_keys %[seq 100 | #{FZF} --header "$(head -5 #{FILE})" --reverse], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  100/100', lines[1]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[2..6]
      assert_equal '> 1', lines[7]
    end
  end

  def test_header_reverse_list
    tmux.send_keys %[seq 100 | #{FZF} --header "$(head -5 #{FILE})" --layout=reverse-list], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  100/100', lines[-2]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[-7..-3]
      assert_equal '> 1', lines[0]
    end
  end

  def test_header_and_header_lines
    tmux.send_keys %[seq 100 | #{FZF} --header-lines 10 --header "$(head -5 #{FILE})"], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  90/90', lines[-2]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[-7...-2]
      assert_equal ('  1'..'  10').to_a.reverse, lines[-17...-7]
    end
  end

  def test_header_and_header_lines_reverse
    tmux.send_keys %[seq 100 | #{FZF} --reverse --header-lines 10 --header "$(head -5 #{FILE})"], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  90/90', lines[1]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[2...7]
      assert_equal ('  1'..'  10').to_a, lines[7...17]
    end
  end

  def test_header_and_header_lines_reverse_list
    tmux.send_keys %[seq 100 | #{FZF} --layout=reverse-list --header-lines 10 --header "$(head -5 #{FILE})"], :Enter
    header = File.readlines(FILE, chomp: true).take(5)
    tmux.until do |lines|
      assert_equal '  90/90', lines[-2]
      assert_equal header.map { |line| "  #{line}".rstrip }, lines[-7...-2]
      assert_equal ('  1'..'  10').to_a.reverse, lines[-17...-7]
    end
  end

  def test_toggle_header
    tmux.send_keys "seq 4 | #{FZF} --header-lines 2 --header foo --bind space:toggle-header --header-first --height 10 --border rounded", :Enter
    before = <<~OUTPUT
      ╭───────
      │
      │   4
      │ > 3
      │   2/2
      │ >
      │   2
      │   1
      │   foo
      ╰───────
    OUTPUT
    tmux.until { assert_block(before, _1) }
    tmux.send_keys :Space
    after = <<~OUTPUT
      ╭───────
      │
      │
      │
      │
      │   4
      │ > 3
      │   2/2
      │ >
      ╰───────
    OUTPUT
    tmux.until { assert_block(after, _1) }
    tmux.send_keys :Space
    tmux.until { assert_block(before, _1) }
  end

  def test_cancel
    tmux.send_keys "seq 10 | #{FZF} --bind 2:cancel", :Enter
    tmux.until { |lines| assert_equal '  10/10', lines[-2] }
    tmux.send_keys '123'
    tmux.until do |lines|
      assert_equal '> 3', lines[-1]
      assert_equal '  1/10', lines[-2]
    end
    tmux.send_keys 'C-y', 'C-y'
    tmux.until { |lines| assert_equal '> 311', lines[-1] }
    tmux.send_keys 2
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys 2
    tmux.prepare
  end

  def test_margin
    tmux.send_keys "yes | head -1000 | #{FZF} --margin 5,3", :Enter
    tmux.until do |lines|
      assert_equal '', lines[4]
      assert_equal '     y', lines[5]
    end
    tmux.send_keys :Enter
  end

  def test_margin_reverse
    tmux.send_keys "seq 1000 | #{FZF} --margin 7,5 --reverse", :Enter
    tmux.until { |lines| assert_equal '       1000/1000', lines[1 + 7] }
    tmux.send_keys :Enter
  end

  def test_margin_reverse_list
    tmux.send_keys "yes | head -1000 | #{FZF} --margin 5,3 --layout=reverse-list", :Enter
    tmux.until do |lines|
      assert_equal '', lines[4]
      assert_equal '   > y', lines[5]
    end
    tmux.send_keys :Enter
  end

  def test_tabstop
    writelines(%W[f\too\tba\tr\tbaz\tbarfooq\tux])
    {
      1 => '> f oo ba r baz barfooq ux',
      2 => '> f oo  ba  r baz barfooq ux',
      3 => '> f  oo ba r  baz   barfooq  ux',
      4 => '> f   oo  ba  r   baz barfooq ux',
      5 => '> f    oo   ba   r    baz  barfooq   ux',
      6 => '> f     oo    ba    r     baz   barfooq     ux',
      7 => '> f      oo     ba     r      baz    barfooq       ux',
      8 => '> f       oo      ba      r       baz     barfooq ux',
      9 => '> f        oo       ba       r        baz      barfooq  ux'
    }.each do |ts, exp|
      tmux.prepare
      tmux.send_keys %(cat #{tempname} | fzf --tabstop=#{ts}), :Enter
      tmux.until(true) do |lines|
        assert_equal exp, lines[-3]
      end
      tmux.send_keys :Enter
    end
  end

  def test_with_nth_basic
    writelines(['hello world ', 'byebye'])
    assert_equal \
      'hello world ',
      `#{FZF} -f"^he hehe" -x -n 2.. --with-nth 2,1,1 < #{tempname}`.chomp
  end

  def test_with_nth_ansi
    writelines(["\x1b[33mhello \x1b[34;1mworld\x1b[m ", 'byebye'])
    assert_equal \
      'hello world ',
      `#{FZF} -f"^he hehe" -x -n 2.. --with-nth 2,1,1 --ansi < #{tempname}`.chomp
  end

  def test_with_nth_no_ansi
    src = "\x1b[33mhello \x1b[34;1mworld\x1b[m "
    writelines([src, 'byebye'])
    assert_equal \
      src,
      `#{FZF} -fhehe -x -n 2.. --with-nth 2,1,1 --no-ansi < #{tempname}`.chomp
  end

  def test_exit_0_exit_code
    `echo foo | #{FZF} -q bar -0`
    assert_equal 1, $CHILD_STATUS.exitstatus
  end

  def test_invalid_option
    lines = `#{FZF} --foobar 2>&1`
    assert_equal 2, $CHILD_STATUS.exitstatus
    assert_includes lines, 'unknown option: --foobar'
  end

  def test_filter_exitstatus
    # filter / streaming filter
    ['', '--no-sort'].each do |opts|
      assert_includes `echo foo | #{FZF} -f foo #{opts}`, 'foo'
      assert_equal 0, $CHILD_STATUS.exitstatus

      assert_empty `echo foo | #{FZF} -f bar #{opts}`
      assert_equal 1, $CHILD_STATUS.exitstatus
    end
  end

  def test_exitstatus_empty
    { '99' => '0', '999' => '1' }.each do |query, status|
      tmux.send_keys "seq 100 | #{FZF} -q #{query}; echo --$?--", :Enter
      tmux.until { |lines| assert_match %r{ [10]/100}, lines[-2] }
      tmux.send_keys :Enter
      tmux.until { |lines| assert_equal "--#{status}--", lines.last }
    end
  end

  def test_default_extended
    assert_equal '100', `seq 100 | #{FZF} -f "1 00$"`.chomp
    assert_equal '', `seq 100 | #{FZF} -f "1 00$" +x`.chomp
  end

  def test_exact
    assert_equal 4, `seq 123 | #{FZF} -f 13`.lines.length
    assert_equal 2, `seq 123 | #{FZF} -f 13 -e`.lines.length
    assert_equal 4, `seq 123 | #{FZF} -f 13 +e`.lines.length
  end

  def test_or_operator
    assert_equal %w[1 5 10], `seq 10 | #{FZF} -f "1 | 5"`.lines(chomp: true)
    assert_equal %w[1 10 2 3 4 5 6 7 8 9],
                 `seq 10 | #{FZF} -f '1 | !1'`.lines(chomp: true)
  end

  def test_hscroll_off
    writelines(['=' * 10_000 + '0123456789'])
    [0, 3, 6].each do |off|
      tmux.prepare
      tmux.send_keys "#{FZF} --hscroll-off=#{off} -q 0 < #{tempname}", :Enter
      tmux.until { |lines| assert lines[-3]&.end_with?((0..off).to_a.join + '··') }
      tmux.send_keys '9'
      tmux.until { |lines| assert lines[-3]&.end_with?('789') }
      tmux.send_keys :Enter
    end
  end

  def test_partial_caching
    tmux.send_keys 'seq 1000 | fzf -e', :Enter
    tmux.until { |lines| assert_equal '  1000/1000', lines[-2] }
    tmux.send_keys 11
    tmux.until { |lines| assert_equal '  19/1000', lines[-2] }
    tmux.send_keys 'C-a', "'"
    tmux.until { |lines| assert_equal '  28/1000', lines[-2] }
    tmux.send_keys :Enter
  end

  def test_jump
    tmux.send_keys "seq 1000 | #{fzf("--multi --jump-labels 12345 --bind 'ctrl-j:jump'")}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_equal '5 5', lines[-7] }
    tmux.until { |lines| assert_equal '  6', lines[-8] }
    tmux.send_keys '5'
    tmux.until { |lines| assert_equal '> 5', lines[-7] }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal ' >5', lines[-7] }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_equal '5>5', lines[-7] }
    tmux.send_keys '2'
    tmux.until { |lines| assert_equal '> 2', lines[-4] }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal ' >2', lines[-4] }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_equal '5>5', lines[-7] }

    # Press any key other than jump labels to cancel jump
    tmux.send_keys '6'
    tmux.until { |lines| assert_equal '> 1', lines[-3] }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal '>>1', lines[-3] }
    tmux.send_keys :Enter
    assert_equal %w[5 2 1], fzf_output_lines
  end

  def test_jump_accept
    tmux.send_keys "seq 1000 | #{fzf("--multi --jump-labels 12345 --bind 'ctrl-j:jump-accept'")}", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_equal '5 5', lines[-7] }
    tmux.send_keys '3'
    assert_equal '3', fzf_output
  end

  def test_jump_events
    tmux.send_keys "seq 1000 | #{FZF} --multi --jump-labels 12345 --bind 'ctrl-j:jump,jump:preview(echo jumped to {}),jump-cancel:preview(echo jump cancelled at {})'", :Enter
    tmux.until { |lines| assert_equal '  1000/1000 (0)', lines[-2] }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_includes lines[-7], '5 5' }
    tmux.send_keys '3'
    tmux.until { |lines| assert(lines.any? { _1.include?('jumped to 3') }) }
    tmux.send_keys 'C-j'
    tmux.until { |lines| assert_includes lines[-7], '5 5' }
    tmux.send_keys 'C-c'
    tmux.until { |lines| assert(lines.any? { _1.include?('jump cancelled at 3') }) }
  end

  def test_pointer
    tmux.send_keys "seq 10 | #{fzf("--pointer '>>'")}", :Enter
    # Assert that specified pointer is displayed
    tmux.until { |lines| assert_equal '>> 1', lines[-3] }
  end

  def test_pointer_with_jump
    tmux.send_keys "seq 10 | #{FZF} --multi --jump-labels 12345 --bind 'ctrl-j:jump' --pointer '>>'", :Enter
    tmux.until { |lines| assert_equal '  10/10 (0)', lines[-2] }
    tmux.send_keys 'C-j'
    # Correctly padded jump label should appear
    tmux.until { |lines| assert_equal '5  5', lines[-7] }
    tmux.until { |lines| assert_equal '   6', lines[-8] }
    tmux.send_keys '5'
    # Assert that specified pointer is displayed
    tmux.until { |lines| assert_equal '>> 5', lines[-7] }
  end

  def test_marker
    tmux.send_keys "seq 10 | #{FZF} --multi --marker '>>'", :Enter
    tmux.until { |lines| assert_equal '  10/10 (0)', lines[-2] }
    tmux.send_keys :BTab
    # Assert that specified marker is displayed
    tmux.until { |lines| assert_equal ' >>1', lines[-3] }
  end

  def test_preview
    tmux.send_keys %(seq 1000 | sed s/^2$// | #{FZF} -m --preview 'sleep 0.2; echo {{}-{+}}' --bind ?:toggle-preview), :Enter
    tmux.until { |lines| assert_includes lines[1], ' {1-1} ' }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[1], ' {-} ' }
    tmux.send_keys '555'
    tmux.until { |lines| assert_includes lines[1], ' {555-555} ' }
    tmux.send_keys '?'
    tmux.until { |lines| refute_includes lines[1], ' {555-555} ' }
    tmux.send_keys '?'
    tmux.until { |lines| assert_includes lines[1], ' {555-555} ' }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert lines[-2]&.start_with?('  28/1000 ') }
    tmux.send_keys 'foobar'
    tmux.until { |lines| refute_includes lines[1], ' {55-55} ' }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' {1-1} ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {-1} ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {3-1 } ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {4-1  3} ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {5-1  3 4} ' }
  end

  def test_toggle_preview_without_default_preview_command
    tmux.send_keys %(seq 100 | #{FZF} --bind 'space:preview(echo [{}]),enter:toggle-preview' --preview-window up,border-double), :Enter
    tmux.until do |lines|
      assert_equal 100, lines.match_count
      refute_includes lines[1], '║ [1]'
    end

    # toggle-preview should do nothing
    tmux.send_keys :Enter
    tmux.until { |lines| refute_includes lines[1], '║ [1]' }
    tmux.send_keys :Up
    tmux.until do |lines|
      refute_includes lines[1], '║ [1]'
      refute_includes lines[1], '║ [2]'
    end

    tmux.send_keys :Up
    tmux.until do |lines|
      assert_includes lines, '> 3'
      refute_includes lines[1], '║ [3]'
    end

    # One-off preview action
    tmux.send_keys :Space
    tmux.until { |lines| assert_includes lines[1], '║ [3]' }

    # toggle-preview to hide it
    tmux.send_keys :Enter
    tmux.until { |lines| refute_includes lines[1], '║ [3]' }

    # toggle-preview again does nothing
    tmux.send_keys :Enter, :Up
    tmux.until do |lines|
      assert_includes lines, '> 4'
      refute_includes lines[1], '║ [4]'
    end
  end

  def test_show_and_hide_preview
    tmux.send_keys %(seq 100 | #{FZF} --preview-window hidden,border-bold --preview 'echo [{}]' --bind 'a:show-preview,b:hide-preview'), :Enter

    # Hidden by default
    tmux.until do |lines|
      assert_equal 100, lines.match_count
      refute_includes lines[1], '┃ [1]'
    end

    # Show
    tmux.send_keys :a
    tmux.until { |lines| assert_includes lines[1], '┃ [1]' }

    # Already shown
    tmux.send_keys :a
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[1], '┃ [2]' }

    # Hide
    tmux.send_keys :b
    tmux.send_keys :Up
    tmux.until do |lines|
      assert_includes lines, '> 3'
      refute_includes lines[1], '┃ [3]'
    end

    # Already hidden
    tmux.send_keys :b
    tmux.send_keys :Up
    tmux.until do |lines|
      assert_includes lines, '> 4'
      refute_includes lines[1], '┃ [4]'
    end

    # Show it again
    tmux.send_keys :a
    tmux.until { |lines| assert_includes lines[1], '┃ [4]' }
  end

  def test_preview_hidden
    tmux.send_keys %(seq 1000 | #{FZF} --preview 'echo {{}-{}-$FZF_PREVIEW_LINES-$FZF_PREVIEW_COLUMNS}' --preview-window down:1:hidden --bind ?:toggle-preview), :Enter
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys '?'
    tmux.until { |lines| assert_match(/ {1-1-1-[0-9]+}/, lines[-2]) }
    tmux.send_keys '555'
    tmux.until { |lines| assert_match(/ {555-555-1-[0-9]+}/, lines[-2]) }
    tmux.send_keys '?'
    tmux.until { |lines| assert_equal '> 555', lines[-1] }
  end

  def test_preview_size_0
    tmux.send_keys %(seq 100 | #{FZF} --reverse --preview 'echo {} >> #{tempname}; echo ' --preview-window 0 --bind space:toggle-preview), :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal '  100/100', lines[1]
      assert_equal '> 1', lines[2]
    end
    wait do
      assert_path_exists tempname
      assert_equal %w[1], File.readlines(tempname, chomp: true)
    end
    tmux.send_keys :Space, :Down, :Down
    tmux.until { |lines| assert_equal '> 3', lines[4] }
    wait do
      assert_path_exists tempname
      assert_equal %w[1], File.readlines(tempname, chomp: true)
    end
    tmux.send_keys :Space, :Down
    tmux.until { |lines| assert_equal '> 4', lines[5] }
    wait do
      assert_path_exists tempname
      assert_equal %w[1 3 4], File.readlines(tempname, chomp: true)
    end
  end

  def test_preview_size_0_hidden
    tmux.send_keys %(seq 100 | #{FZF} --reverse --preview 'echo {} >> #{tempname}; echo ' --preview-window 0,hidden --bind space:toggle-preview), :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys :Down, :Down
    tmux.until { |lines| assert_includes lines, '> 3' }
    wait { refute_path_exists tempname }
    tmux.send_keys :Space
    wait do
      assert_path_exists tempname
      assert_equal %w[3], File.readlines(tempname, chomp: true)
    end
    tmux.send_keys :Down
    wait do
      assert_equal %w[3 4], File.readlines(tempname, chomp: true)
    end
    tmux.send_keys :Space, :Down
    tmux.until { |lines| assert_includes lines, '> 5' }
    tmux.send_keys :Down
    tmux.until { |lines| assert_includes lines, '> 6' }
    tmux.send_keys :Space
    wait do
      assert_equal %w[3 4 6], File.readlines(tempname, chomp: true)
    end
  end

  def test_preview_flags
    tmux.send_keys %(seq 10 | sed 's/^/:: /; s/$/  /' |
        #{FZF} --multi --preview 'echo {{2}/{s2}/{+2}/{+s2}/{q}/{n}/{+n}}'), :Enter
    tmux.until { |lines| assert_includes lines[1], ' {1/1  /1/1  //0/0} ' }
    tmux.send_keys '123'
    tmux.until { |lines| assert_includes lines[1], ' {////123//} ' }
    tmux.send_keys 'C-u', '1'
    tmux.until { |lines| assert_equal 2, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' {1/1  /1/1  /1/0/0} ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {10/10  /1/1  /1/9/0} ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' {10/10  /1 10/1   10  /1/9/0 9} ' }
    tmux.send_keys '2'
    tmux.until { |lines| assert_includes lines[1], ' {//1 10/1   10  /12//0 9} ' }
    tmux.send_keys '3'
    tmux.until { |lines| assert_includes lines[1], ' {//1 10/1   10  /123//0 9} ' }
  end

  def test_preview_file
    tmux.send_keys %[(echo foo bar; echo bar foo) | #{FZF} --multi --preview 'cat {+f} {+f2} {+nf} {+fn}' --print0], :Enter
    tmux.until { |lines| assert_includes lines[1], ' foo barbar00 ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' foo barbar00 ' }
    tmux.send_keys :BTab
    tmux.until { |lines| assert_includes lines[1], ' foo barbar foobarfoo0101 ' }
  end

  def test_preview_q_no_match
    tmux.send_keys %(: | #{FZF} --preview 'echo foo {q} foo'), :Enter
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' foo  foo' }
    tmux.send_keys 'bar'
    tmux.until { |lines| assert_includes lines[1], ' foo bar foo' }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_includes lines[1], ' foo  foo' }
  end

  def test_preview_q_no_match_with_initial_query
    tmux.send_keys %(: | #{FZF} --preview 'echo foo {q}{q}' --query foo), :Enter
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' foofoo ' }
  end

  def test_no_clear
    tmux.send_keys "seq 10 | #{fzf('--no-clear --inline-info --height 5')}", :Enter
    prompt = '>   < 10/10'
    tmux.until { |lines| assert_equal prompt, lines[-1] }
    tmux.send_keys :Enter
    assert_equal %w[1], fzf_output_lines
    tmux.until { |lines| assert_equal prompt, lines[-1] }
  end

  def test_info_hidden
    tmux.send_keys 'seq 10 | fzf --info=hidden --no-separator', :Enter
    tmux.until { |lines| assert_equal '> 1', lines[-2] }
  end

  def test_info_inline_separator
    tmux.send_keys 'seq 10 | fzf --info=inline:___ --no-separator', :Enter
    tmux.until { |lines| assert_equal '>  ___10/10', lines[-1] }
  end

  def test_change_first_last
    tmux.send_keys %(seq 1000 | #{FZF} --bind change:first,alt-Z:last), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal '> 2', lines[-4] }
    tmux.send_keys 1
    tmux.until { |lines| assert_equal '> 1', lines[-3] }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal '> 10', lines[-4] }
    tmux.send_keys 1
    tmux.until { |lines| assert_equal '> 11', lines[-3] }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal '> 1', lines[-3] }
    tmux.send_keys :Escape, 'Z'
    tmux.until { |lines| assert_equal '> 1000', lines[0] }
    tmux.send_keys :Enter
  end

  def test_pos
    tmux.send_keys %(seq 1000 | #{FZF} --bind 'a:pos(3),b:pos(-3),c:pos(1),d:pos(-1),e:pos(0)' --preview 'echo {}/{}'), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys :a
    tmux.until { |lines| assert_includes lines[1], ' 3/3' }
    tmux.send_keys :b
    tmux.until { |lines| assert_includes lines[1], ' 998/998' }
    tmux.send_keys :c
    tmux.until { |lines| assert_includes lines[1], ' 1/1' }
    tmux.send_keys :d
    tmux.until { |lines| assert_includes lines[1], ' 1000/1000' }
    tmux.send_keys :e
    tmux.until { |lines| assert_includes lines[1], ' 1/1' }
  end

  def test_put
    tmux.send_keys %(seq 1000 | #{FZF} --bind 'a:put+put,b:put+put(ravo)' --preview 'echo {q}/{q}'), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys :a
    tmux.until { |lines| assert_includes lines[1], ' aa/aa' }
    tmux.send_keys :b
    tmux.until { |lines| assert_includes lines[1], ' aabravo/aabravo' }
  end

  def test_accept_non_empty
    tmux.send_keys %(seq 1000 | #{fzf('--print-query --bind enter:accept-non-empty')}), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys 'foo'
    tmux.until { |lines| assert_equal '  0/1000', lines[-2] }
    # fzf doesn't exit since there's no selection
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal '  0/1000', lines[-2] }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal '  1000/1000', lines[-2] }
    tmux.send_keys '999'
    tmux.until { |lines| assert_equal '  1/1000', lines[-2] }
    tmux.send_keys :Enter
    assert_equal %w[999 999], fzf_output_lines
  end

  def test_accept_non_empty_with_multi_selection
    tmux.send_keys %(seq 1000 | #{fzf('-m --print-query --bind enter:accept-non-empty')}), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal '  1000/1000 (1)', lines[-2] }
    tmux.send_keys 'foo'
    tmux.until { |lines| assert_equal '  0/1000 (1)', lines[-2] }
    # fzf will exit in this case even though there's no match for the current query
    tmux.send_keys :Enter
    assert_equal %w[foo 1], fzf_output_lines
  end

  def test_accept_non_empty_with_empty_list
    tmux.send_keys %(: | #{fzf('-q foo --print-query --bind enter:accept-non-empty')}), :Enter
    tmux.until { |lines| assert_equal '  0/0', lines[-2] }
    tmux.send_keys :Enter
    # fzf will exit anyway since input list is empty
    assert_equal %w[foo], fzf_output_lines
  end

  def test_accept_or_print_query_without_match
    tmux.send_keys %(seq 1000 | #{fzf('--bind enter:accept-or-print-query')}), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys 99_999
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.send_keys :Enter
    assert_equal %w[99999], fzf_output_lines
  end

  def test_accept_or_print_query_with_match
    tmux.send_keys %(seq 1000 | #{fzf('--bind enter:accept-or-print-query')}), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys '^99$'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter
    assert_equal %w[99], fzf_output_lines
  end

  def test_accept_or_print_query_with_multi_selection
    tmux.send_keys %(seq 1000 | #{fzf('--bind enter:accept-or-print-query --multi')}), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys :BTab, :BTab, :BTab
    tmux.until { |lines| assert_equal 3, lines.select_count }
    tmux.send_keys 99_999
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.send_keys :Enter
    assert_equal %w[1 2 3], fzf_output_lines
  end

  def test_preview_update_on_select
    tmux.send_keys %(seq 10 | fzf -m --preview 'echo {+}' --bind a:toggle-all),
                   :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.send_keys 'a'
    tmux.until { |lines| assert(lines.any? { |line| line.include?(' 1 2 3 4 5 ') }) }
    tmux.send_keys 'a'
    tmux.until { |lines| lines.each { |line| refute_includes line, ' 1 2 3 4 5 ' } }
  end

  def test_escaped_meta_characters
    input = [
      'foo^bar',
      'foo$bar',
      'foo!bar',
      "foo'bar",
      'foo bar',
      'bar foo'
    ]
    writelines(input)

    assert_equal input.length, `#{FZF} -f'foo bar' < #{tempname}`.lines.length
    assert_equal input.length - 1, `#{FZF} -f'^foo bar$' < #{tempname}`.lines.length
    assert_equal ['foo bar'], `#{FZF} -f'foo\\ bar' < #{tempname}`.lines(chomp: true)
    assert_equal ['foo bar'], `#{FZF} -f'^foo\\ bar$' < #{tempname}`.lines(chomp: true)
    assert_equal input.length - 1, `#{FZF} -f'!^foo\\ bar$' < #{tempname}`.lines.length
  end

  def test_inverse_only_search_should_not_sort_the_result
    # Filter
    assert_equal %w[aaaaa b ccc],
                 `printf '%s\n' aaaaa b ccc BAD | #{FZF} -f '!bad'`.lines(chomp: true)

    # Interactive
    tmux.send_keys %(printf '%s\n' aaaaa b ccc BAD | #{FZF} -q '!bad'), :Enter
    tmux.until do |lines|
      assert_equal 4, lines.item_count
      assert_equal 3, lines.match_count
    end
    tmux.until { |lines| assert_equal '> aaaaa', lines[-3] }
    tmux.until { |lines| assert_equal '  b', lines[-4] }
    tmux.until { |lines| assert_equal '  ccc', lines[-5] }
  end

  def test_preview_correct_tab_width_after_ansi_reset_code
    writelines(["\x1b[31m+\x1b[m\t\x1b[32mgreen"])
    tmux.send_keys "#{FZF} --preview 'cat #{tempname}'", :Enter
    tmux.until { |lines| assert_includes lines[1], ' +       green ' }
  end

  def test_disabled
    tmux.send_keys %(seq 1000 | #{FZF} --query 333 --disabled --bind a:enable-search,b:disable-search,c:toggle-search --preview 'echo {} {q}'), :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' 1 333 ' }
    tmux.send_keys 'foo'
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' 1 333foo ' }

    # Already disabled, no change
    tmux.send_keys 'b'
    tmux.until { |lines| assert_equal 1000, lines.match_count }

    # Enable search
    tmux.send_keys 'a'
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.send_keys :BSpace, :BSpace, :BSpace
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' 333 333 ' }

    # Toggle search -> disabled again, but retains the previous result
    tmux.send_keys 'c'
    tmux.send_keys 'foo'
    tmux.until { |lines| assert_includes lines[1], ' 333 333foo ' }
    tmux.until { |lines| assert_equal 1, lines.match_count }

    # Enabled, no match
    tmux.send_keys 'c'
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], ' 333foo ' }
  end

  def test_reload
    tmux.send_keys %(seq 1000 | #{FZF} --bind 'change:reload(seq $FZF_QUERY),a:reload(seq 100),b:reload:seq 200' --header-lines 2 --multi 2), :Enter
    tmux.until { |lines| assert_equal 998, lines.match_count }
    tmux.send_keys 'a'
    tmux.until do |lines|
      assert_equal 98, lines.item_count
      assert_equal 98, lines.match_count
    end
    tmux.send_keys 'b'
    tmux.until do |lines|
      assert_equal 198, lines.item_count
      assert_equal 198, lines.match_count
    end
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal '  198/198 (1/2)', lines[-2] }
    tmux.send_keys '555'
    tmux.until { |lines| assert_equal '  1/553 (0/2)', lines[-2] }
  end

  def test_reload_even_when_theres_no_match
    tmux.send_keys %(: | #{FZF} --bind 'space:reload(seq 10)'), :Enter
    tmux.until { |lines| assert_equal 0, lines.item_count }
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal 10, lines.item_count }
  end

  def test_reload_should_terminate_standard_input_stream
    tmux.send_keys %(ruby -e "STDOUT.sync = true; loop { puts 1; sleep 0.1 }" | fzf --bind 'start:reload(seq 100)'), :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
  end

  def test_clear_list_when_header_lines_changed_due_to_reload
    tmux.send_keys %(seq 10 | #{FZF} --header 0 --header-lines 3 --bind 'space:reload(seq 1)'), :Enter
    tmux.until { |lines| assert_includes lines, '  9' }
    tmux.send_keys :Space
    tmux.until { |lines| refute_includes lines, '  9' }
  end

  def test_clear_query
    tmux.send_keys %(: | #{FZF} --query foo --bind space:clear-query), :Enter
    tmux.until { |lines| assert_equal 0, lines.item_count }
    tmux.until { |lines| assert_equal '> foo', lines.last }
    tmux.send_keys 'C-a', 'bar'
    tmux.until { |lines| assert_equal '> barfoo', lines.last }
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal '>', lines.last }
  end

  def test_change_and_transform_header
    [
      'space:change-header:$(seq 4)',
      'space:transform-header:seq 4'
    ].each_with_index do |binding, i|
      tmux.send_keys %(seq 3 | #{FZF} --header-lines 2 --header bar --bind "#{binding}"), :Enter
      expected = <<~OUTPUT
        > 3
          2
          1
          bar
          1/1
        >
      OUTPUT
      tmux.until { assert_block(expected, _1) }
      tmux.send_keys :Space
      expected = <<~OUTPUT
        > 3
          2
          1
          1
          2
          3
          4
          1/1
        >
      OUTPUT
      tmux.until { assert_block(expected, _1) }
      next unless i.zero?

      teardown
      setup
    end
  end

  def test_change_header
    tmux.send_keys %(seq 3 | #{FZF} --header-lines 2 --header bar --bind "space:change-header:$(seq 4)"), :Enter
    expected = <<~OUTPUT
      > 3
        2
        1
        bar
        1/1
      >
    OUTPUT
    tmux.until { assert_block(expected, _1) }
    tmux.send_keys :Space
    expected = <<~OUTPUT
      > 3
        2
        1
        1
        2
        3
        4
        1/1
      >
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_change_query
    tmux.send_keys %(: | #{FZF} --query foo --bind space:change-query:foobar), :Enter
    tmux.until { |lines| assert_equal 0, lines.item_count }
    tmux.until { |lines| assert_equal '> foo', lines.last }
    tmux.send_keys :Space, 'baz'
    tmux.until { |lines| assert_equal '> foobarbaz', lines.last }
  end

  def test_transform_query
    tmux.send_keys %{#{FZF} --bind 'ctrl-r:transform-query(rev <<< {q}),ctrl-u:transform-query: tr "[:lower:]" "[:upper:]" <<< {q}' --query bar}, :Enter
    tmux.until { |lines| assert_equal '> bar', lines[-1] }
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_equal '> rab', lines[-1] }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal '> RAB', lines[-1] }
  end

  def test_transform_prompt
    tmux.send_keys %{#{FZF} --bind 'ctrl-r:transform-query(rev <<< {q}),ctrl-u:transform-query: tr "[:lower:]" "[:upper:]" <<< {q}' --query bar}, :Enter
    tmux.until { |lines| assert_equal '> bar', lines[-1] }
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_equal '> rab', lines[-1] }
    tmux.send_keys 'C-u'
    tmux.until { |lines| assert_equal '> RAB', lines[-1] }
  end

  def test_transform
    tmux.send_keys %{#{FZF} --bind 'focus:transform:echo "change-prompt({fzf:action})"'}, :Enter
    tmux.until { |lines| assert_equal 'start', lines[-1] }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal 'up', lines[-1] }
  end

  def test_clear_selection
    tmux.send_keys %(seq 100 | #{FZF} --multi --bind space:clear-selection), :Enter
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal '  100/100 (1)', lines[-2] }
    tmux.send_keys 'foo'
    tmux.until { |lines| assert_equal '  0/100 (1)', lines[-2] }
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal '  0/100 (0)', lines[-2] }
  end

  def test_backward_delete_char_eof
    tmux.send_keys "seq 1000 | #{FZF} --bind 'bs:backward-delete-char/eof'", :Enter
    tmux.until { |lines| assert_equal '  1000/1000', lines[-2] }
    tmux.send_keys '11'
    tmux.until { |lines| assert_equal '> 11', lines[-1] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '> 1', lines[-1] }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys :BSpace
    tmux.prepare
  end

  def test_strip_xterm_osc_sequence
    %W[\x07 \x1b\\].each do |esc|
      writelines([%(printf $1"\e]4;3;rgb:aa/bb/cc#{esc} "$2)])
      File.chmod(0o755, tempname)
      tmux.prepare
      tmux.send_keys \
        %(echo foo bar | #{FZF} --preview '#{tempname} {2} {1}'), :Enter

      tmux.until { |lines| assert lines.any_include?('bar foo') }
      tmux.send_keys :Enter
    end
  end

  def test_keep_right
    tmux.send_keys "seq 10000 | #{FZF} --read0 --keep-right --no-multi-line", :Enter
    tmux.until { |lines| assert lines.any_include?('9999␊10000') }
  end

  def test_backward_eof
    tmux.send_keys "echo foo | #{FZF} --bind 'backward-eof:reload(seq 100)'", :Enter
    tmux.until { |lines| lines.item_count == 1 && lines.match_count == 1 }
    tmux.send_keys 'x'
    tmux.until { |lines| lines.item_count == 1 && lines.match_count == 0 }
    tmux.send_keys :BSpace
    tmux.until { |lines| lines.item_count == 1 && lines.match_count == 1 }
    tmux.send_keys :BSpace
    tmux.until { |lines| lines.item_count == 100 && lines.match_count == 100 }
  end

  def test_preview_bindings_with_default_preview
    tmux.send_keys "seq 10 | #{FZF} --preview 'echo [{}]' --bind 'a:preview(echo [{}{}]),b:preview(echo [{}{}{}]),c:refresh-preview'", :Enter
    tmux.until { |lines| lines.item_count == 10 }
    tmux.until { |lines| assert_includes lines[1], '[1]' }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[1], '[11]' }
    tmux.send_keys 'c'
    tmux.until { |lines| assert_includes lines[1], '[1]' }
    tmux.send_keys 'b'
    tmux.until { |lines| assert_includes lines[1], '[111]' }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[1], '[2]' }
  end

  def test_preview_bindings_without_default_preview
    tmux.send_keys "seq 10 | #{FZF} --bind 'a:preview(echo [{}{}]),b:preview(echo [{}{}{}]),c:refresh-preview'", :Enter
    tmux.until { |lines| lines.item_count == 10 }
    tmux.until { |lines| refute_includes lines[1], '1' }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[1], '[11]' }
    tmux.send_keys 'c' # does nothing
    tmux.until { |lines| assert_includes lines[1], '[11]' }
    tmux.send_keys 'b'
    tmux.until { |lines| assert_includes lines[1], '[111]' }
    tmux.send_keys 9
    tmux.until { |lines| lines.match_count == 1 }
    tmux.until { |lines| refute_includes lines[1], '2' }
    tmux.until { |lines| assert_includes lines[1], '[111]' }
  end

  def test_preview_scroll_begin_constant
    tmux.send_keys "echo foo 123 321 | #{FZF} --preview 'seq 1000' --preview-window left:+123", :Enter
    tmux.until { |lines| assert_match %r{1/1}, lines[-2] }
    tmux.until { |lines| assert_match %r{123.*123/1000}, lines[1] }
  end

  def test_preview_scroll_begin_expr
    tmux.send_keys "echo foo 123 321 | #{FZF} --preview 'seq 1000' --preview-window left:+{3}", :Enter
    tmux.until { |lines| assert_match %r{1/1}, lines[-2] }
    tmux.until { |lines| assert_match %r{321.*321/1000}, lines[1] }
  end

  def test_preview_scroll_begin_and_offset
    ['echo foo 123 321', 'echo foo :123: 321'].each do |input|
      tmux.send_keys "#{input} | #{FZF} --preview 'seq 1000' --preview-window left:+{2}-2", :Enter
      tmux.until { |lines| assert_match %r{1/1}, lines[-2] }
      tmux.until { |lines| assert_match %r{121.*121/1000}, lines[1] }
      tmux.send_keys 'C-c'
    end
  end

  def test_normalized_match
    echoes = '(echo a; echo á; echo A; echo Á;)'
    assert_equal %w[a á A Á], `#{echoes} | #{FZF} -f a`.lines.map(&:chomp)
    assert_equal %w[á Á], `#{echoes} | #{FZF} -f á`.lines.map(&:chomp)
    assert_equal %w[A Á], `#{echoes} | #{FZF} -f A`.lines.map(&:chomp)
    assert_equal %w[Á], `#{echoes} | #{FZF} -f Á`.lines.map(&:chomp)
  end

  def test_preview_clear_screen
    tmux.send_keys %{seq 100 | #{FZF} --preview 'for i in $(seq 300); do (( i % 200 == 0 )) && printf "\\033[2J"; echo "[$i]"; sleep 0.001; done'}, :Enter
    tmux.until { |lines| lines.item_count == 100 }
    tmux.until { |lines| lines[1]&.include?('[200]') }
  end

  def test_change_prompt
    tmux.send_keys "#{FZF} --bind 'a:change-prompt(a> ),b:change-prompt:b> ' --query foo", :Enter
    tmux.until { |lines| assert_equal '> foo', lines[-1] }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_equal 'a> foo', lines[-1] }
    tmux.send_keys 'b'
    tmux.until { |lines| assert_equal 'b> foo', lines[-1] }
  end

  def test_preview_window_follow
    file = Tempfile.new('fzf-follow')
    file.sync = true

    tmux.send_keys %(seq 100 | #{FZF} --preview 'echo start; tail -f "#{file.path}"' --preview-window follow --bind 'up:preview-up,down:preview-down,space:change-preview-window:follow|nofollow' --preview-window '~4'), :Enter
    tmux.until { |lines| lines.item_count == 100 }

    # Write to the temporary file, and check if the preview window is showing
    # the last line of the file
    tmux.until { |lines| assert_includes lines[1], 'start' }
    3.times { file.puts _1 } # header lines
    1000.times { file.puts _1 }
    tmux.until { |lines| assert_includes lines[1], '/1004' }
    tmux.until { |lines| assert_includes lines[-2], '999' }

    # Scroll the preview window and fzf should stop following the file content
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[-2], '998' }
    file.puts 'foo', 'bar'
    tmux.until do |lines|
      assert_includes lines[1], '/1006'
      assert_includes lines[-2], '998'
    end

    # Scroll back to the bottom and fzf should start following the file again
    %w[999 foo bar].each do |item|
      wait do
        tmux.send_keys :Down
        tmux.until { |lines| assert_includes lines[-2], item }
      end
    end
    file.puts 'baz'
    tmux.until do |lines|
      assert_includes lines[1], '/1007'
      assert_includes lines[-2], 'baz'
    end

    # Scroll upwards to stop following
    tmux.send_keys :Up
    wait { assert_includes lines[-2], 'bar' }
    file.puts 'aaa'
    tmux.until do |lines|
      assert_includes lines[1], '/1008'
      assert_includes lines[-2], 'bar'
    end

    # Manually enable following
    tmux.send_keys :Space
    tmux.until { |lines| assert_includes lines[-2], 'aaa' }
    file.puts 'bbb'
    tmux.until do |lines|
      assert_includes lines[1], '/1009'
      assert_includes lines[-2], 'bbb'
    end

    # Disable following
    tmux.send_keys :Space
    file.puts 'ccc', 'ddd'
    tmux.until do |lines|
      assert_includes lines[1], '/1011'
      assert_includes lines[-2], 'bbb'
    end
  rescue StandardError
    file.close
    file.unlink
  end

  def test_toggle_preview_wrap
    tmux.send_keys "#{FZF} --preview 'for i in $(seq $FZF_PREVIEW_COLUMNS); do echo -n .; done; echo wrapped; echo 2nd line' --bind ctrl-w:toggle-preview-wrap", :Enter
    2.times do
      tmux.until { |lines| assert_includes lines[2], '2nd line' }
      tmux.send_keys 'C-w'
      tmux.until do |lines|
        assert_includes lines[2], 'wrapped'
        assert_includes lines[3], '2nd line'
      end
      tmux.send_keys 'C-w'
    end
  end

  def test_close
    tmux.send_keys "seq 100 | #{FZF} --preview 'echo foo' --bind ctrl-c:close", :Enter
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.until { |lines| assert_includes lines[1], 'foo' }
    tmux.send_keys 'C-c'
    tmux.until { |lines| refute_includes lines[1], 'foo' }
    tmux.send_keys '10'
    tmux.until { |lines| assert_equal 2, lines.match_count }
    tmux.send_keys 'C-c'
    tmux.send_keys 'C-l', 'closed'
    tmux.until { |lines| assert_includes lines[0], 'closed' }
  end

  def test_select_deselect
    tmux.send_keys "seq 3 | #{FZF} --multi --bind up:deselect+up,down:select+down", :Enter
    tmux.until { |lines| assert_equal 3, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 1, lines.select_count }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal 0, lines.select_count }
    tmux.send_keys :Down, :Down
    tmux.until { |lines| assert_equal 2, lines.select_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 1, lines.select_count }
    tmux.send_keys :Down, :Down
    tmux.until { |lines| assert_equal 2, lines.select_count }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal 1, lines.select_count }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal 1, lines.select_count }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal 2, lines.select_count }
  end

  def test_interrupt_execute
    tmux.send_keys "seq 100 | #{FZF} --bind 'ctrl-l:execute:echo executing {}; sleep 100'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys 'C-l'
    tmux.until { |lines| assert lines.any_include?('executing 1') }
    tmux.send_keys 'C-c'
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys 99
    tmux.until { |lines| assert_equal 1, lines.match_count }
  end

  def test_kill_default_command_on_abort
    writelines(['#!/usr/bin/env bash',
                "echo 'Started'",
                'while :; do sleep 1; done'])
    system("chmod +x #{tempname}")

    tmux.send_keys FZF.sub('FZF_DEFAULT_COMMAND=', "FZF_DEFAULT_COMMAND=#{tempname}"), :Enter
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.send_keys 'C-c'
    tmux.send_keys 'C-l', 'closed'
    tmux.until { |lines| assert_includes lines[0], 'closed' }
    wait { refute system("pgrep -f #{tempname}") }
  ensure
    system("pkill -9 -f #{tempname}")
  end

  def test_kill_default_command_on_accept
    writelines(['#!/usr/bin/env bash',
                "echo 'Started'",
                'while :; do sleep 1; done'])
    system("chmod +x #{tempname}")

    tmux.send_keys fzf.sub('FZF_DEFAULT_COMMAND=', "FZF_DEFAULT_COMMAND=#{tempname}"), :Enter
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.send_keys :Enter
    assert_equal 'Started', fzf_output
    wait { refute system("pgrep -f #{tempname}") }
  ensure
    system("pkill -9 -f #{tempname}")
  end

  def test_kill_reload_command_on_abort
    writelines(['#!/usr/bin/env bash',
                "echo 'Started'",
                'while :; do sleep 1; done'])
    system("chmod +x #{tempname}")

    tmux.send_keys "seq 1 3 | #{FZF} --bind 'ctrl-r:reload(#{tempname})'", :Enter
    tmux.until { |lines| assert_equal 3, lines.item_count }
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.send_keys 'C-c'
    tmux.send_keys 'C-l', 'closed'
    tmux.until { |lines| assert_includes lines[0], 'closed' }
    wait { refute system("pgrep -f #{tempname}") }
  ensure
    system("pkill -9 -f #{tempname}")
  end

  def test_kill_reload_command_on_accept
    writelines(['#!/usr/bin/env bash',
                "echo 'Started'",
                'while :; do sleep 1; done'])
    system("chmod +x #{tempname}")

    tmux.send_keys "seq 1 3 | #{fzf("--bind 'ctrl-r:reload(#{tempname})'")}", :Enter
    tmux.until { |lines| assert_equal 3, lines.item_count }
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.send_keys :Enter
    assert_equal 'Started', fzf_output
    wait { refute system("pgrep -f #{tempname}") }
  ensure
    system("pkill -9 -f #{tempname}")
  end

  def test_preview_header
    tmux.send_keys "seq 100 | #{FZF} --bind ctrl-k:preview-up+preview-up,ctrl-j:preview-down+preview-down+preview-down --preview 'seq 1000' --preview-window 'top:+{1}:~3'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    top5 = ->(lines) { lines.drop(1).take(5).map { |s| s[/[0-9]+/] } }
    tmux.until do |lines|
      assert_includes lines[1], '4/1000'
      assert_equal(%w[1 2 3 4 5], top5[lines])
    end
    tmux.send_keys '55'
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert_equal(%w[1 2 3 55 56], top5[lines])
    end
    tmux.send_keys 'C-J'
    tmux.until do |lines|
      assert_equal(%w[1 2 3 58 59], top5[lines])
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 19, lines.match_count
      assert_equal(%w[1 2 3 5 6], top5[lines])
    end
    tmux.send_keys 'C-K'
    tmux.until { |lines| assert_equal(%w[1 2 3 4 5], top5[lines]) }
  end

  def test_unbind_rebind
    tmux.send_keys "seq 100 | #{FZF} --bind 'c:clear-query,d:unbind(c,d),e:rebind(c,d)'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys 'ab'
    tmux.until { |lines| assert_equal '> ab', lines[-1] }
    tmux.send_keys 'c'
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys 'dabcd'
    tmux.until { |lines| assert_equal '> abcd', lines[-1] }
    tmux.send_keys 'ecabddc'
    tmux.until { |lines| assert_equal '> abdc', lines[-1] }
  end

  def test_item_index_reset_on_reload
    tmux.send_keys "seq 10 | #{FZF} --preview 'echo [[{n}]]' --bind 'up:last,down:first,space:reload:seq 100'", :Enter
    tmux.until { |lines| assert_includes lines[1], '[[0]]' }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[1], '[[9]]' }
    tmux.send_keys :Down
    tmux.until { |lines| assert_includes lines[1], '[[0]]' }
    tmux.send_keys :Space
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_includes lines[1], '[[0]]'
    end
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[1], '[[99]]' }
  end

  def test_reload_should_update_preview
    tmux.send_keys "seq 3 | #{FZF} --bind 'ctrl-t:reload:echo 4' --preview 'echo {}' --preview-window 'nohidden'", :Enter
    tmux.until { |lines| assert_includes lines[1], '1' }
    tmux.send_keys 'C-t'
    tmux.until { |lines| assert_includes lines[1], '4' }
  end

  def test_reload_and_change_preview_should_update_preview
    tmux.send_keys "seq 3 | #{FZF} --bind 'ctrl-t:reload(echo 4)+change-preview(echo {})'", :Enter
    tmux.until { |lines| assert_equal 3, lines.item_count }
    tmux.until { |lines| refute_includes lines[1], '1' }
    tmux.send_keys 'C-t'
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.until { |lines| assert_includes lines[1], '4' }
  end

  def test_reload_sync
    tmux.send_keys "seq 100 | #{FZF} --bind 'load:reload-sync(sleep 1; seq 1000)+unbind(load)'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys '00'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    # After 1 second
    tmux.until { |lines| assert_equal 10, lines.match_count }
  end

  def test_reload_disabled_case1
    tmux.send_keys "seq 100 | #{FZF} --query 99 --bind 'space:disable-search+reload(sleep 2; seq 1000)'", :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.until { |lines| assert_equal 1000, lines.match_count }
  end

  def test_reload_disabled_case2
    tmux.send_keys "seq 100 | #{FZF} --query 99 --bind 'space:disable-search+reload-sync(sleep 2; seq 1000)'", :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.until { |lines| assert_equal 1000, lines.match_count }
  end

  def test_reload_disabled_case3
    tmux.send_keys "seq 100 | #{FZF} --query 99 --bind 'space:disable-search+reload(sleep 2; seq 1000)+backward-delete-char'", :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.until { |lines| assert_equal 1000, lines.match_count }
  end

  def test_reload_disabled_case4
    tmux.send_keys "seq 100 | #{FZF} --query 99 --bind 'space:disable-search+reload-sync(sleep 2; seq 1000)+backward-delete-char'", :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :Space
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.until { |lines| assert_equal 1000, lines.match_count }
  end

  def test_reload_disabled_case5
    tmux.send_keys "seq 100 | #{FZF} --query 99 --bind 'space:disable-search+reload(echo xx; sleep 2; seq 1000)'", :Enter
    tmux.until do |lines|
      assert_equal 100, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :Space
    tmux.until do |lines|
      assert_equal 1, lines.item_count
      assert_equal 1, lines.match_count
    end
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 1001, lines.match_count }
  end

  def test_reload_disabled_case6
    tmux.send_keys "seq 1000 | #{FZF} --disabled --bind 'change:reload:sleep 0.5; seq {q}'", :Enter
    tmux.until { |lines| assert_equal 1000, lines.match_count }
    tmux.send_keys '9'
    tmux.until { |lines| assert_equal 9, lines.match_count }
    tmux.send_keys '9'
    tmux.until { |lines| assert_equal 99, lines.match_count }

    # TODO: How do we verify if an intermediate empty list is not shown?
  end

  def test_scroll_off
    tmux.send_keys "seq 1000 | #{FZF} --scroll-off=3 --bind l:last", :Enter
    tmux.until { |lines| assert_equal 1000, lines.item_count }
    height = tmux.until { |lines| lines }.first.to_i
    tmux.send_keys :PgUp
    tmux.until do |lines|
      assert_equal height + 3, lines.first.to_i
      assert_equal "> #{height}", lines[3].strip
    end
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal "> #{height + 1}", lines[3].strip }
    tmux.send_keys 'l'
    tmux.until { |lines| assert_equal '> 1000', lines.first.strip }
    tmux.send_keys :PgDn
    tmux.until { |lines| assert_equal "> #{1000 - height + 1}", lines.reverse[5].strip }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal "> #{1000 - height}", lines.reverse[5].strip }
  end

  def test_scroll_off_large
    tmux.send_keys "seq 1000 | #{FZF} --scroll-off=9999", :Enter
    tmux.until { |lines| assert_equal 1000, lines.item_count }
    height = tmux.until { |lines| lines }.first.to_i
    tmux.send_keys :PgUp
    tmux.until { |lines| assert_equal "> #{height}", lines[height / 2].strip }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal "> #{height + 1}", lines[height / 2].strip }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal "> #{height + 2}", lines[height / 2].strip }
    tmux.send_keys :Down
    tmux.until { |lines| assert_equal "> #{height + 1}", lines[height / 2].strip }
  end

  def test_header_first
    tmux.send_keys "seq 1000 | #{FZF} --header foobar --header-lines 3 --header-first", :Enter
    tmux.until do |lines|
      expected = <<~OUTPUT
        > 4
          997/997
        >
          3
          2
          1
          foobar
      OUTPUT

      assert_equal expected.chomp, lines.reverse.take(7).reverse.join("\n")
    end
  end

  def test_header_first_reverse
    tmux.send_keys "seq 1000 | #{FZF} --header foobar --header-lines 3 --header-first --reverse --inline-info", :Enter
    tmux.until do |lines|
      expected = <<~OUTPUT
          foobar
          1
          2
          3
        >   < 997/997
        > 4
      OUTPUT

      assert_equal expected.chomp, lines.take(6).join("\n")
    end
  end

  def test_change_preview_window
    tmux.send_keys "seq 1000 | #{FZF} --preview 'echo [[{}]]' --preview-window border-none --bind '" \
      'a:change-preview(echo __{}__),' \
      'b:change-preview-window(down)+change-preview(echo =={}==)+change-preview-window(up),' \
      'c:change-preview(),d:change-preview-window(hidden),' \
      "e:preview(printf ::%${FZF_PREVIEW_COLUMNS}s{})+change-preview-window(up),f:change-preview-window(up,wrap)'", :Enter
    tmux.until { |lines| assert_equal 1000, lines.item_count }
    tmux.until { |lines| assert_includes lines[0], '[[1]]' }

    # change-preview action permanently changes the preview command set by --preview
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[0], '__1__' }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines[0], '__2__' }

    # When multiple change-preview-window actions are bound to a single key,
    # the last one wins and the updated options are immediately applied to the new preview
    tmux.send_keys 'b'
    tmux.until { |lines| assert_equal '==2==', lines[0] }
    tmux.send_keys :Up
    tmux.until { |lines| assert_equal '==3==', lines[0] }

    # change-preview with an empty preview command closes the preview window
    tmux.send_keys 'c'
    tmux.until { |lines| refute_includes lines[0], '==' }

    # change-preview again to re-open the preview window
    tmux.send_keys 'a'
    tmux.until { |lines| assert_equal '__3__', lines[0] }

    # Hide the preview window with hidden flag
    tmux.send_keys 'd'
    tmux.until { |lines| refute_includes lines[0], '__3__' }

    # One-off preview
    tmux.send_keys 'e'
    tmux.until do |lines|
      assert_equal '::', lines[0]
      refute_includes lines[1], '3'
    end

    # Wrapped
    tmux.send_keys 'f'
    tmux.until do |lines|
      assert_equal '::', lines[0]
      assert_equal '  3', lines[1]
    end
  end

  def test_change_preview_window_should_not_reset_change_preview
    tmux.send_keys "#{FZF} --preview-window up,border-none --bind 'start:change-preview(echo hello)' --bind 'enter:change-preview-window(border-left)'", :Enter
    tmux.until { |lines| assert_includes lines, 'hello' }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_includes lines, '│ hello' }
  end

  def test_change_preview_window_rotate
    tmux.send_keys "seq 100 | #{FZF} --preview-window left,border-none --preview 'echo hello' --bind '" \
      "a:change-preview-window(right|down|up|hidden|)'", :Enter
    tmux.until { |lines| assert(lines.any? { _1.include?('100/100') }) }
    3.times do
      tmux.until { |lines| lines[0].start_with?('hello') }
      tmux.send_keys 'a'
      tmux.until { |lines| lines[0].end_with?('hello') }
      tmux.send_keys 'a'
      tmux.until { |lines| lines[-1].start_with?('hello') }
      tmux.send_keys 'a'
      tmux.until { |lines| assert_equal 'hello', lines[0] }
      tmux.send_keys 'a'
      tmux.until { |lines| refute_includes lines[0], 'hello' }
      tmux.send_keys 'a'
    end
  end

  def test_change_preview_window_rotate_hidden
    tmux.send_keys "seq 100 | #{FZF} --preview-window hidden --preview 'echo =={}==' --bind '" \
      "a:change-preview-window(nohidden||down,1|)'", :Enter
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.until { |lines| refute_includes lines[1], '==1==' }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[1], '==1==' }
    tmux.send_keys 'a'
    tmux.until { |lines| refute_includes lines[1], '==1==' }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[-2], '==1==' }
    tmux.send_keys 'a'
    tmux.until { |lines| refute_includes lines[-2], '==1==' }
    tmux.send_keys 'a'
    tmux.until { |lines| assert_includes lines[1], '==1==' }
  end

  def test_change_preview_window_rotate_hidden_down
    tmux.send_keys "seq 100 | #{FZF} --bind '?:change-preview-window:up||down|' --preview 'echo =={}==' --preview-window hidden,down,1", :Enter
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.until { |lines| refute_includes lines[1], '==1==' }
    tmux.send_keys '?'
    tmux.until { |lines| assert_includes lines[1], '==1==' }
    tmux.send_keys '?'
    tmux.until { |lines| refute_includes lines[1], '==1==' }
    tmux.send_keys '?'
    tmux.until { |lines| assert_includes lines[-2], '==1==' }
    tmux.send_keys '?'
    tmux.until { |lines| refute_includes lines[-2], '==1==' }
    tmux.send_keys '?'
    tmux.until { |lines| assert_includes lines[1], '==1==' }
  end

  def test_ellipsis
    tmux.send_keys 'seq 1000 | tr "\n" , | fzf --ellipsis=SNIPSNIP -e -q500', :Enter
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.until { |lines| assert_match(/^> SNIPSNIP.*SNIPSNIP$/, lines[-3]) }
  end

  def assert_block(expected, lines)
    cols = expected.lines.map(&:chomp).map(&:length).max
    top = lines.take(expected.lines.length).map { _1[0, cols].rstrip + "\n" }.join
    bottom = lines.reverse.take(expected.lines.length).reverse.map { _1[0, cols].rstrip + "\n" }.join
    assert_includes [top, bottom], expected
  end

  def test_height_range_fit
    tmux.send_keys 'seq 3 | fzf --height ~100% --info=inline --border rounded', :Enter
    expected = <<~OUTPUT
      ╭──────────
      │   3
      │   2
      │ > 1
      │ >   < 3/3
      ╰──────────
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_height_range_fit_preview_above
    tmux.send_keys 'seq 3 | fzf --height ~100% --info=inline --border rounded --preview-window border-rounded --preview "seq {}" --preview-window up,60%', :Enter
    expected = <<~OUTPUT
      ╭──────────
      │ ╭────────
      │ │ 1
      │ │
      │ │
      │ │
      │ ╰────────
      │   3
      │   2
      │ > 1
      │ >   < 3/3
      ╰──────────
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_height_range_fit_preview_above_alternative
    tmux.send_keys 'seq 3 | fzf --height ~100% --border=sharp --preview "seq {}" --preview-window up,40%,border-bottom --padding 1 --exit-0 --header hello --header-lines=2', :Enter
    expected = <<~OUTPUT
      ┌─────────
      │
      │  1
      │  2
      │  3
      │  ───────
      │  > 3
      │    2
      │    1
      │    hello
      │    1/1 ─
      │  >
      │
      └─────────
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_height_range_fit_preview_left
    tmux.send_keys "seq 3 | fzf --height ~100% --border=vertical --preview 'seq {}' --preview-window left,5,border-right --padding 1 --exit-0 --header $'hello\\nworld' --header-lines=2", :Enter
    expected = <<~OUTPUT
      │
      │  1     │ > 3
      │  2     │   2
      │  3     │   1
      │        │   hello
      │        │   world
      │        │   1/1 ─
      │        │ >
      │
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_height_range_overflow
    tmux.send_keys 'seq 100 | fzf --height ~5 --info=inline --border rounded', :Enter
    expected = <<~OUTPUT
      ╭──────────────
      │   2
      │ > 1
      │ >   < 100/100
      ╰──────────────
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_start_event
    tmux.send_keys 'seq 100 | fzf --multi --sync --preview-window hidden:border-none --bind "start:select-all+last+preview(echo welcome)"', :Enter
    tmux.until do |lines|
      assert_match(/>100.*welcome/, lines[0])
      assert_includes(lines[-2], '100/100 (100)')
    end
  end

  def test_focus_event
    tmux.send_keys 'seq 100 | fzf --bind "focus:transform-prompt(echo [[{}]]),?:unbind(focus)"', :Enter
    tmux.until { |lines| assert_includes(lines[-1], '[[1]]') }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes(lines[-1], '[[2]]') }
    tmux.send_keys :X
    tmux.until { |lines| assert_includes(lines[-1], '[[]]') }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_includes(lines[-1], '[[1]]') }
    tmux.send_keys :X
    tmux.until { |lines| assert_includes(lines[-1], '[[]]') }
    tmux.send_keys '?'
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 100, lines.match_count }
    tmux.until { |lines| refute_includes(lines[-1], '[[1]]') }
  end

  def test_result_event
    tmux.send_keys '(echo 0; seq 10) | fzf --bind "result:pos(2)"', :Enter
    tmux.until { |lines| assert_equal 11, lines.item_count }
    tmux.until { |lines| assert_includes lines, '> 1' }
    tmux.send_keys '9'
    tmux.until { |lines| assert_includes lines, '> 9' }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_includes lines, '> 1' }
  end

  def test_labels_center
    tmux.send_keys 'echo x | fzf --border --border-label foobar --preview : --preview-label barfoo --bind "space:change-border-label(foobarfoo)+change-preview-label(barfoobar),enter:transform-border-label(echo foo{}foo)+transform-preview-label(echo bar{}bar)"', :Enter
    tmux.until do
      assert_includes(_1[0], '─foobar─')
      assert_includes(_1[1], '─barfoo─')
    end
    tmux.send_keys :space
    tmux.until do
      assert_includes(_1[0], '─foobarfoo─')
      assert_includes(_1[1], '─barfoobar─')
    end
    tmux.send_keys :Enter
    tmux.until do
      assert_includes(_1[0], '─fooxfoo─')
      assert_includes(_1[1], '─barxbar─')
    end
  end

  def test_labels_left
    tmux.send_keys ': | fzf --border rounded --preview-window border-rounded --border-label foobar --border-label-pos 2 --preview : --preview-label barfoo --preview-label-pos 2', :Enter
    tmux.until do
      assert_includes(_1[0], '╭foobar─')
      assert_includes(_1[1], '╭barfoo─')
    end
  end

  def test_labels_right
    tmux.send_keys ': | fzf --border rounded --preview-window border-rounded --border-label foobar --border-label-pos -2 --preview : --preview-label barfoo --preview-label-pos -2', :Enter
    tmux.until do
      assert_includes(_1[0], '─foobar╮')
      assert_includes(_1[1], '─barfoo╮')
    end
  end

  def test_labels_bottom
    tmux.send_keys ': | fzf --border rounded --preview-window border-rounded --border-label foobar --border-label-pos 2:bottom --preview : --preview-label barfoo --preview-label-pos -2:bottom', :Enter
    tmux.until do
      assert_includes(_1[-1], '╰foobar─')
      assert_includes(_1[-2], '─barfoo╯')
    end
  end

  def test_labels_variables
    tmux.send_keys ': | fzf --border --border-label foobar --preview "echo \$FZF_BORDER_LABEL // \$FZF_PREVIEW_LABEL" --preview-label barfoo --bind "space:change-border-label(barbaz)+change-preview-label(bazbar)+refresh-preview,enter:transform-border-label(echo 123)+transform-preview-label(echo 456)+refresh-preview"', :Enter
    tmux.until do
      assert_includes(_1[0], '─foobar─')
      assert_includes(_1[1], '─barfoo─')
      assert_includes(_1[2], ' foobar // barfoo ')
    end
    tmux.send_keys :Space
    tmux.until do
      assert_includes(_1[0], '─barbaz─')
      assert_includes(_1[1], '─bazbar─')
      assert_includes(_1[2], ' barbaz // bazbar ')
    end
    tmux.send_keys :Enter
    tmux.until do
      assert_includes(_1[0], '─123─')
      assert_includes(_1[1], '─456─')
      assert_includes(_1[2], ' 123 // 456 ')
    end
  end

  def test_info_separator_unicode
    tmux.send_keys 'seq 100 | fzf -q55', :Enter
    tmux.until { assert_includes(_1[-2], '  1/100 ─') }
  end

  def test_info_separator_no_unicode
    tmux.send_keys 'seq 100 | fzf -q55 --no-unicode', :Enter
    tmux.until { assert_includes(_1[-2], '  1/100 -') }
  end

  def test_info_separator_repeat
    tmux.send_keys 'seq 100 | fzf -q55 --separator _-', :Enter
    tmux.until { assert_includes(_1[-2], '  1/100 _-_-') }
  end

  def test_info_separator_ansi_colors_and_tabs
    tmux.send_keys "seq 100 | fzf -q55 --tabstop 4 --separator $'\\x1b[33ma\\tb'", :Enter
    tmux.until { assert_includes(_1[-2], '  1/100 a   ba   ba') }
  end

  def test_info_no_separator
    tmux.send_keys 'seq 100 | fzf -q55 --no-separator', :Enter
    tmux.until { assert(_1[-2] == '  1/100') }
  end

  def test_info_right
    tmux.send_keys "#{FZF} --info=right --separator x --bind 'start:reload:seq 100; sleep 10'", :Enter
    tmux.until { assert_match(%r{xxx [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] 100/100}, _1[-2]) }
  end

  def test_info_inline_right
    tmux.send_keys "#{FZF} --info=inline-right --bind 'start:reload:seq 100; sleep 10'", :Enter
    tmux.until { assert_match(%r{[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] 100/100}, _1[-1]) }
  end

  def test_info_inline_right_clearance
    tmux.send_keys "seq 100000 | #{FZF} --info inline-right", :Enter
    tmux.until { assert_match(%r{100000/100000}, _1[-1]) }
    tmux.send_keys 'x'
    tmux.until { assert_match(%r{     0/100000}, _1[-1]) }
  end

  def test_info_command
    tmux.send_keys(%(seq 10000 | #{FZF} --separator x --info-command 'echo -e "--\\x1b[33m$FZF_POS\\x1b[m/$FZF_INFO--"'), :Enter)
    tmux.until { assert_match(%r{^  --1/10000/10000-- xx}, _1[-2]) }
    tmux.send_keys :Up
    tmux.until { assert_match(%r{^  --2/10000/10000-- xx}, _1[-2]) }
  end

  def test_info_command_inline
    tmux.send_keys(%(seq 10000 | #{FZF} --separator x --info-command 'echo -e "--\\x1b[33m$FZF_POS\\x1b[m/$FZF_INFO--"' --info inline:xx), :Enter)
    tmux.until { assert_match(%r{^>  xx--1/10000/10000-- xx}, _1[-1]) }
  end

  def test_info_command_right
    tmux.send_keys(%(seq 10000 | #{FZF} --separator x --info-command 'echo -e "--\\x1b[33m$FZF_POS\\x1b[m/$FZF_INFO--"' --info right), :Enter)
    tmux.until { assert_match(%r{xx --1/10000/10000-- *$}, _1[-2]) }
  end

  def test_info_command_inline_right
    tmux.send_keys(%(seq 10000 | #{FZF} --info-command 'echo -e "--\\x1b[33m$FZF_POS\\x1b[m/$FZF_INFO--"' --info inline-right), :Enter)
    tmux.until { assert_match(%r{   --1/10000/10000-- *$}, _1[-1]) }
  end

  def test_prev_next_selected
    tmux.send_keys 'seq 10 | fzf --multi --bind ctrl-n:next-selected,ctrl-p:prev-selected', :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.send_keys :BTab, :BTab, :Up, :BTab
    tmux.until { |lines| assert_equal 3, lines.select_count }
    tmux.send_keys 'C-n'
    tmux.until { |lines| assert_includes lines, '>>4' }
    tmux.send_keys 'C-n'
    tmux.until { |lines| assert_includes lines, '>>2' }
    tmux.send_keys 'C-n'
    tmux.until { |lines| assert_includes lines, '>>1' }
    tmux.send_keys 'C-n'
    tmux.until { |lines| assert_includes lines, '>>4' }
    tmux.send_keys 'C-p'
    tmux.until { |lines| assert_includes lines, '>>1' }
    tmux.send_keys 'C-p'
    tmux.until { |lines| assert_includes lines, '>>2' }
  end

  def test_listen
    { '--listen 6266' => -> { URI('http://localhost:6266') },
      "--listen --sync --bind 'start:execute-silent:echo $FZF_PORT > /tmp/fzf-port'" =>
        -> { URI("http://localhost:#{File.read('/tmp/fzf-port').chomp}") } }.each do |opts, fn|
      tmux.send_keys "seq 10 | fzf #{opts}", :Enter
      tmux.until { |lines| assert_equal 10, lines.item_count }
      state = JSON.parse(Net::HTTP.get(fn.call), symbolize_names: true)
      assert_equal 10, state[:totalCount]
      assert_equal 10, state[:matchCount]
      assert_empty state[:query]
      assert_equal({ index: 0, text: '1' }, state[:current])

      Net::HTTP.post(fn.call, 'change-query(yo)+reload(seq 100)+change-prompt:hundred> ')
      tmux.until { |lines| assert_equal 100, lines.item_count }
      tmux.until { |lines| assert_equal 'hundred> yo', lines[-1] }
      state = JSON.parse(Net::HTTP.get(fn.call), symbolize_names: true)
      assert_equal 100, state[:totalCount]
      assert_equal 0, state[:matchCount]
      assert_equal 'yo', state[:query]
      assert_nil state[:current]

      teardown
      setup
    end
  end

  def test_listen_with_api_key
    post_uri = URI('http://localhost:6266')
    tmux.send_keys 'seq 10 | FZF_API_KEY=123abc fzf --listen 6266', :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    # Incorrect API Key
    [nil, { 'x-api-key' => '' }, { 'x-api-key' => '124abc' }].each do |headers|
      res = Net::HTTP.post(post_uri, 'change-query(yo)+reload(seq 100)+change-prompt:hundred> ', headers)
      assert_equal '401', res.code
      assert_equal 'Unauthorized', res.message
      assert_equal "invalid api key\n", res.body
    end
    # Valid API Key
    [{ 'x-api-key' => '123abc' }, { 'X-API-Key' => '123abc' }].each do |headers|
      res = Net::HTTP.post(post_uri, 'change-query(yo)+reload(seq 100)+change-prompt:hundred> ', headers)
      assert_equal '200', res.code
      tmux.until { |lines| assert_equal 100, lines.item_count }
      tmux.until { |lines| assert_equal 'hundred> yo', lines[-1] }
    end
  end

  def test_toggle_alternative_preview_window
    tmux.send_keys "seq 10 | #{FZF} --bind space:toggle-preview --preview-window '<100000(hidden,up,border-none)' --preview 'echo /{}/{}/'", :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.until { |lines| refute_includes lines, '/1/1/' }
    tmux.send_keys :Space
    tmux.until { |lines| assert_includes lines, '/1/1/' }
  end

  def test_alternative_preview_window_opts
    tmux.send_keys "seq 10 | #{FZF} --preview-window '~5,2,+0,<100000(~0,+100,wrap,noinfo)' --preview 'seq 1000'", :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.until do |lines|
      assert_equal ['╭────╮', '│ 10 │', '│ 0  │', '│ 10 │', '│ 1  │'], lines.take(5).map(&:strip)
    end
  end

  def test_preview_window_width_exception
    tmux.send_keys "seq 10 | #{FZF} --scrollbar --preview-window border-left --border --preview 'seq 1000'", :Enter
    tmux.until do |lines|
      assert lines[1]&.end_with?(' 1/1000││')
    end
  end

  def test_become
    tmux.send_keys "seq 100 | #{FZF} --bind 'enter:become:seq {} | #{FZF}'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys 999
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 0, lines.match_count }
    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 99, lines.item_count }
  end

  def test_no_extra_newline_issue_3209
    tmux.send_keys(%(seq 100 | #{FZF} --height 10 --preview-window up,wrap,border-rounded --preview 'printf "─%.0s" $(seq 1 "$((FZF_PREVIEW_COLUMNS - 5))"); printf $"\\e[7m%s\\e[0m" title; echo; echo something'), :Enter)
    expected = <<~OUTPUT
      ╭──────────
      │ ─────────
      │ something
      │
      ╰──────────
        3
        2
      > 1
        100/100 ─
      >
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_track
    tmux.send_keys "seq 1000 | #{FZF} --query 555 --track --bind t:toggle-track", :Enter
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert_includes lines, '> 555'
    end
    tmux.send_keys :BSpace
    index = tmux.until do |lines|
      assert_equal 28, lines.match_count
      assert_includes lines, '> 555'
    end.index('> 555')
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 271, lines.match_count
      assert_equal '> 555', lines[index]
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 1000, lines.match_count
      assert_equal '> 555', lines[index]
    end
    tmux.send_keys '555'
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert_includes lines, '> 555'
      assert_includes lines[-2], '+T'
    end
    tmux.send_keys 't'
    tmux.until do |lines|
      refute_includes lines[-2], '+T'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 28, lines.match_count
      assert_includes lines, '> 55'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 271, lines.match_count
      assert_includes lines, '> 5'
    end
    tmux.send_keys 't'
    tmux.until do |lines|
      assert_includes lines[-2], '+T'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 1000, lines.match_count
      assert_includes lines, '> 5'
    end
  end

  def test_track_action
    tmux.send_keys "seq 1000 | #{FZF} --query 555 --bind t:track", :Enter
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert_includes lines, '> 555'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 28, lines.match_count
      assert_includes lines, '> 55'
    end
    tmux.send_keys :t
    tmux.until do |lines|
      assert_includes lines[-2], '+t'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 271, lines.match_count
      assert_includes lines, '> 55'
    end

    # Automatically disabled when the tracking item is no longer visible
    tmux.send_keys '4'
    tmux.until do |lines|
      assert_equal 28, lines.match_count
      refute_includes lines[-2], '+t'
    end
    tmux.send_keys :BSpace
    tmux.until do |lines|
      assert_equal 271, lines.match_count
      assert_includes lines, '> 5'
    end
    tmux.send_keys :t
    tmux.until do |lines|
      assert_includes lines[-2], '+t'
    end
    tmux.send_keys :Up
    tmux.until do |lines|
      refute_includes lines[-2], '+t'
    end
  end

  def test_one_and_zero
    tmux.send_keys "seq 10 | #{FZF} --bind 'zero:preview(echo no match),one:preview(echo {} is the only match)'", :Enter
    tmux.send_keys '1'
    tmux.until do |lines|
      assert_equal 2, lines.match_count
      refute(lines.any? { _1.include?('only match') })
      refute(lines.any? { _1.include?('no match') })
    end
    tmux.send_keys '0'
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert(lines.any? { _1.include?('only match') })
    end
    tmux.send_keys '0'
    tmux.until do |lines|
      assert_equal 0, lines.match_count
      assert(lines.any? { _1.include?('no match') })
    end
  end

  def test_height_range_with_exit_0
    tmux.send_keys "seq 10 | #{FZF} --height ~10% --exit-0", :Enter
    tmux.until { |lines| assert_equal 10, lines.item_count }
    tmux.send_keys :c
    tmux.until { |lines| assert_equal 0, lines.match_count }
  end

  def test_reload_and_change
    tmux.send_keys "(echo foo; echo bar) | #{FZF} --bind 'load:reload-sync(sleep 60)+change-query(bar)'", :Enter
    tmux.until { |lines| assert_equal 1, lines.match_count }
  end

  def test_reload_and_change_cache
    tmux.send_keys "echo bar | #{FZF} --bind 'zero:change-header(foo)+reload(echo foo)+clear-query'", :Enter
    expected = <<~OUTPUT
      > bar
        1/1
      >
    OUTPUT
    tmux.until { assert_block(expected, _1) }
    tmux.send_keys :z
    expected = <<~OUTPUT
      > foo
        foo
        1/1
      >
    OUTPUT
    tmux.until { assert_block(expected, _1) }
  end

  def test_delete_with_modifiers
    if ENV['GITHUB_ACTION']
      # Expected: "[3]"
      # Actual: "[]3;5~"
      skip('CTRL-DELETE is not properly handled in GitHub Actions environment')
    end
    tmux.send_keys "seq 100 | #{FZF} --bind 'ctrl-delete:up+up,shift-delete:down,focus:transform-prompt:echo [{}]'", :Enter
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys 'C-Delete'
    tmux.until { |lines| assert_equal '[3]', lines[-1] }
    tmux.send_keys 'S-Delete'
    tmux.until { |lines| assert_equal '[2]', lines[-1] }
  end

  def test_become_tty
    tmux.send_keys "sleep 0.5 | #{FZF} --bind 'start:reload:ls' --bind 'load:become:tty'", :Enter
    tmux.until { |lines| assert_includes lines, '/dev/tty' }
  end

  def test_disabled_preview_update
    tmux.send_keys "echo bar | #{FZF} --disabled --bind 'change:reload:echo foo' --preview 'echo [{q}-{}]'", :Enter
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.until { |lines| assert(lines.any? { |line| line.include?('[-bar]') }) }
    tmux.send_keys :x
    tmux.until { |lines| assert(lines.any? { |line| line.include?('[x-foo]') }) }
  end

  def test_preview_window_hidden_on_focus
    tmux.send_keys "seq 3 | #{FZF} --preview 'echo {}' --bind focus:hide-preview", :Enter
    tmux.until { |lines| assert_includes lines, '> 1' }
    tmux.send_keys :Up
    tmux.until { |lines| assert_includes lines, '> 2' }
  end

  def test_fzf_pos
    tmux.send_keys "seq 100 | #{FZF} --preview 'echo $FZF_POS / $FZF_MATCH_COUNT'", :Enter
    tmux.until { |lines| assert(lines.any? { |line| line.include?('1 / 100') }) }
    tmux.send_keys :Up
    tmux.until { |lines| assert(lines.any? { |line| line.include?('2 / 100') }) }
    tmux.send_keys '99'
    tmux.until { |lines| assert(lines.any? { |line| line.include?('1 / 1') }) }
    tmux.send_keys '99'
    tmux.until { |lines| assert(lines.any? { |line| line.include?('0 / 0') }) }
  end

  def test_fzf_multi_line
    tmux.send_keys %[(echo -en '0\\0'; echo -en '1\\n2\\0'; seq 1000) | fzf --read0 --multi --bind load:select-all --border rounded], :Enter
    block = <<~BLOCK
      │  ┃998
      │  ┃999
      │  ┃1000
      │  ╹
      │  ╻1
      │  ╹2
      │ >>0
      │   3/3 (3)
      │ >
      ╰───────────
    BLOCK
    tmux.until { assert_block(block, _1) }
    tmux.send_keys :Up, :Up
    block = <<~BLOCK
      ╭───────
      │ >╻1
      │ >┃2
      │ >┃3
    BLOCK
    tmux.until { assert_block(block, _1) }

    block = <<~BLOCK
      │ >┃
      │
      │ >
      ╰───
    BLOCK
    tmux.until { assert_block(block, _1) }
  end

  def test_fzf_multi_line_reverse
    tmux.send_keys %[(echo -en '0\\0'; echo -en '1\\n2\\0'; seq 1000) | fzf --read0 --multi --bind load:select-all --border rounded --reverse], :Enter
    block = <<~BLOCK
      ╭───────────
      │ >
      │   3/3 (3)
      │ >>0
      │  ╻1
      │  ╹2
      │  ╻1
      │  ┃2
      │  ┃3
    BLOCK
    tmux.until { assert_block(block, _1) }
  end

  def test_fzf_multi_line_no_pointer_and_marker
    tmux.send_keys %[(echo -en '0\\0'; echo -en '1\\n2\\0'; seq 1000) | fzf --read0 --multi --bind load:select-all --border rounded --reverse --pointer '' --marker '' --marker-multi-line ''], :Enter
    block = <<~BLOCK
      ╭───────────
      │ >
      │   3/3 (3)
      │ 0
      │ 1
      │ 2
      │ 1
      │ 2
      │ 3
    BLOCK
    tmux.until { assert_block(block, _1) }
  end

  def test_start_on_reload
    tmux.send_keys %(echo foo | #{FZF} --header Loading --header-lines 1 --bind 'start:reload:sleep 2; echo bar' --bind 'load:change-header:Loaded' --bind space:change-header:), :Enter
    tmux.until(timeout: 1) { |lines| assert_includes lines[-3], 'Loading' }
    tmux.until(timeout: 1) { |lines| refute_includes lines[-4], 'foo' }
    tmux.until { |lines| assert_includes lines[-3], 'Loaded' }
    tmux.until { |lines| assert_includes lines[-4], 'bar' }
    tmux.send_keys :Space
    tmux.until { |lines| assert_includes lines[-3], 'bar' }
  end

  def test_boundary_match
    # Underscore boundaries should be ranked lower
    {
      default: [' x '] + %w[/x/ [x] -x- -x_ _x- _x_],
      path: ['/x/', ' x '] + %w[[x] -x- -x_ _x- _x_],
      history: ['[x]', '-x-', ' x '] + %w[/x/ -x_ _x- _x_]
    }.each do |scheme, expected|
      result = `printf -- 'xxx\n-xx\nxx-\n_x_\n_x-\n-x_\n[x]\n-x-\n x \n/x/\n' | #{FZF} -f"'x'" --scheme=#{scheme}`.lines(chomp: true)
      assert_equal expected, result
    end
  end

  def test_preview_window_noinfo
    # │ 1        ││
    tmux.send_keys %(#{FZF} --preview 'seq 1000' --preview-window top,noinfo --scrollbar --bind space:change-preview-window:info), :Enter
    tmux.until do |lines|
      assert lines[1]&.start_with?('│ 1')
      assert lines[1]&.end_with?('  ││')
    end
    tmux.send_keys :Space
    tmux.until do |lines|
      assert lines[1]&.start_with?('│ 1')
      assert lines[1]&.end_with?('1000││')
    end
  end

  def test_gap
    tmux.send_keys %(seq 100 | #{FZF} --gap --border --reverse), :Enter
    block = <<~BLOCK
      ╭─────────────────
      │ >
      │   100/100 ──────
      │ > 1
      │
      │   2
      │
      │   3
      │
      │   4
    BLOCK
    tmux.until { assert_block(block, _1) }
  end

  def test_gap_2
    tmux.send_keys %(seq 100 | #{FZF} --gap=2 --border --reverse), :Enter
    block = <<~BLOCK
      ╭─────────────────
      │ >
      │   100/100 ──────
      │ > 1
      │
      │
      │   2
      │
      │
      │   3
    BLOCK
    tmux.until { assert_block(block, _1) }
  end
end

module TestShell
  def setup
    @tmux = Tmux.new(shell)
    tmux.prepare
  end

  def teardown
    @tmux.kill
  end

  def set_var(name, val)
    tmux.prepare
    tmux.send_keys "export #{name}='#{val}'", :Enter
    tmux.prepare
  end

  def unset_var(name)
    tmux.prepare
    tmux.send_keys "unset #{name}", :Enter
    tmux.prepare
  end

  def test_ctrl_t
    set_var('FZF_CTRL_T_COMMAND', 'seq 100')

    tmux.prepare
    tmux.send_keys 'C-t'
    tmux.until { |lines| assert_equal 100, lines.item_count }
    tmux.send_keys :Tab, :Tab, :Tab
    tmux.until { |lines| assert lines.any_include?(' (3)') }
    tmux.send_keys :Enter
    tmux.until { |lines| assert lines.any_include?('1 2 3') }
    tmux.send_keys 'C-c'
  end

  def test_ctrl_t_unicode
    writelines(['fzf-unicode 테스트1', 'fzf-unicode 테스트2'])
    set_var('FZF_CTRL_T_COMMAND', "cat #{tempname}")

    tmux.prepare
    tmux.send_keys 'echo ', 'C-t'
    tmux.until { |lines| assert_equal 2, lines.item_count }
    tmux.send_keys 'fzf-unicode'
    tmux.until { |lines| assert_equal 2, lines.match_count }

    tmux.send_keys '1'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 1, lines.select_count }

    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 2, lines.match_count }

    tmux.send_keys '2'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 2, lines.select_count }

    tmux.send_keys :Enter
    tmux.until { |lines| assert_match(/echo .*fzf-unicode.*1.* .*fzf-unicode.*2/, lines.join) }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 'fzf-unicode 테스트1 fzf-unicode 테스트2', lines[-1] }
  end

  def test_alt_c
    tmux.prepare
    tmux.send_keys :Escape, :c
    lines = tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    expected = lines.reverse.find { |l| l.start_with?('> ') }[2..]
    tmux.send_keys :Enter
    tmux.prepare
    tmux.send_keys :pwd, :Enter
    tmux.until { |lines| assert lines[-1]&.end_with?(expected) }
  end

  def test_alt_c_command
    set_var('FZF_ALT_C_COMMAND', 'echo /tmp')

    tmux.prepare
    tmux.send_keys 'cd /', :Enter

    tmux.prepare
    tmux.send_keys :Escape, :c
    tmux.until { |lines| assert_equal 1, lines.item_count }
    tmux.send_keys :Enter

    tmux.prepare
    tmux.send_keys :pwd, :Enter
    tmux.until { |lines| assert_equal '/tmp', lines[-1] }
  end

  def test_ctrl_r
    tmux.prepare
    tmux.send_keys 'echo 1st', :Enter
    tmux.prepare
    tmux.send_keys 'echo 2nd', :Enter
    tmux.prepare
    tmux.send_keys 'echo 3d', :Enter
    tmux.prepare
    3.times do
      tmux.send_keys 'echo 3rd', :Enter
      tmux.prepare
    end
    tmux.send_keys 'echo 4th', :Enter
    tmux.prepare
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys 'e3d'
    # Duplicates removed: 3d (1) + 3rd (1) => 2 matches
    tmux.until { |lines| assert_equal 2, lines.match_count }
    tmux.until { |lines| assert lines[-3]&.end_with?(' echo 3d') }
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert lines[-3]&.end_with?(' echo 3rd') }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 'echo 3rd', lines[-1] }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal '3rd', lines[-1] }
  end

  def test_ctrl_r_multiline
    # NOTE: Current bash implementation shows an extra new line if there's
    # only entry in the history
    tmux.send_keys ':', :Enter
    tmux.send_keys 'echo "foo', :Enter, 'bar"', :Enter
    tmux.until { |lines| assert_equal %w[foo bar], lines[-2..] }
    tmux.prepare
    tmux.send_keys 'C-r'
    tmux.until { |lines| assert_equal '>', lines[-1] }
    tmux.send_keys 'foo bar'
    tmux.until { |lines| assert lines[-4]&.match?(/"foo/) } unless shell == :zsh
    tmux.until { |lines| assert lines[-3]&.match?(/bar"␊?/) }
    tmux.send_keys :Enter
    tmux.until { |lines| assert lines[-1]&.match?(/bar"␊?/) }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal %w[foo bar], lines[-2..] }
  end

  def test_ctrl_r_abort
    skip("doesn't restore the original line when search is aborted pre Bash 4") if shell == :bash && `#{Shell.bash} --version`[/(?<= version )\d+/].to_i < 4
    %w[foo ' "].each do |query|
      tmux.prepare
      tmux.send_keys :Enter, query
      tmux.until { |lines| assert lines[-1]&.start_with?(query) }
      tmux.send_keys 'C-r'
      tmux.until { |lines| assert_equal "> #{query}", lines[-1] }
      tmux.send_keys 'C-g'
      tmux.until { |lines| assert lines[-1]&.start_with?(query) }
    end
  end
end

module CompletionTest
  def test_file_completion
    FileUtils.mkdir_p('/tmp/fzf-test')
    FileUtils.mkdir_p('/tmp/fzf test')
    (1..100).each { |i| FileUtils.touch("/tmp/fzf-test/#{i}") }
    ['no~such~user', '/tmp/fzf test/foobar'].each do |f|
      FileUtils.touch(File.expand_path(f))
    end
    tmux.prepare
    tmux.send_keys 'cat /tmp/fzf-test/10**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys ' !d'
    tmux.until { |lines| assert_equal 2, lines.match_count }
    tmux.send_keys :Tab, :Tab
    tmux.until { |lines| assert_equal 2, lines.select_count }
    tmux.send_keys :Enter
    tmux.until(true) do |lines|
      assert_equal 'cat /tmp/fzf-test/10 /tmp/fzf-test/100', lines[-1]
    end

    # ~USERNAME**<TAB>
    user = `whoami`.chomp
    tmux.send_keys 'C-u'
    tmux.send_keys "cat ~#{user}**", :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys "/#{user}"
    tmux.until { |lines| assert(lines.any? { |l| l.end_with?("/#{user}") }) }
    tmux.send_keys :Enter
    tmux.until(true) do |lines|
      assert_match %r{cat .*/#{user}}, lines[-1]
    end

    # ~INVALID_USERNAME**<TAB>
    tmux.send_keys 'C-u'
    tmux.send_keys 'cat ~such**', :Tab
    tmux.until(true) { |lines| assert lines.any_include?('no~such~user') }
    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_equal 'cat no~such~user', lines[-1] }

    # /tmp/fzf\ test**<TAB>
    tmux.send_keys 'C-u'
    tmux.send_keys 'cat /tmp/fzf\ test/**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys 'foobar$'
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert lines.any_include?('> /tmp/fzf test/foobar')
    end
    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_equal 'cat /tmp/fzf\ test/foobar', lines[-1] }

    # Should include hidden files
    (1..100).each { |i| FileUtils.touch("/tmp/fzf-test/.hidden-#{i}") }
    tmux.send_keys 'C-u'
    tmux.send_keys 'cat /tmp/fzf-test/hidden**', :Tab
    tmux.until(true) do |lines|
      assert_equal 100, lines.match_count
      assert lines.any_include?('/tmp/fzf-test/.hidden-')
    end
    tmux.send_keys :Enter
  ensure
    ['/tmp/fzf-test', '/tmp/fzf test', '~/.fzf-home', 'no~such~user'].each do |f|
      FileUtils.rm_rf(File.expand_path(f))
    end
  end

  def test_file_completion_root
    tmux.send_keys 'ls /**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys :Enter
  end

  def test_dir_completion
    (1..100).each do |idx|
      FileUtils.mkdir_p("/tmp/fzf-test/d#{idx}")
    end
    FileUtils.touch('/tmp/fzf-test/d55/xxx')
    tmux.prepare
    tmux.send_keys 'cd /tmp/fzf-test/**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys :Tab, :Tab # Tab does not work here
    tmux.send_keys 55
    tmux.until do |lines|
      assert_equal 1, lines.match_count
      assert_includes lines, '> 55'
      assert_includes lines, '> /tmp/fzf-test/d55'
    end
    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_equal 'cd /tmp/fzf-test/d55/', lines[-1] }
    tmux.send_keys :xx
    tmux.until { |lines| assert_equal 'cd /tmp/fzf-test/d55/xx', lines[-1] }

    # Should not match regular files (bash-only)
    if instance_of?(TestBash)
      tmux.send_keys :Tab
      tmux.until { |lines| assert_equal 'cd /tmp/fzf-test/d55/xx', lines[-1] }
    end

    # Fail back to plusdirs
    tmux.send_keys :BSpace, :BSpace, :BSpace
    tmux.until { |lines| assert_equal 'cd /tmp/fzf-test/d55', lines[-1] }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 'cd /tmp/fzf-test/d55/', lines[-1] }
  end

  def test_process_completion
    tmux.send_keys 'sleep 12345 &', :Enter
    lines = tmux.until { |lines| assert lines[-1]&.start_with?('[1] ') }
    pid = lines[-1]&.split&.last
    tmux.prepare
    tmux.send_keys 'C-L'
    tmux.send_keys 'kill **', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys 'sleep12345'
    tmux.until { |lines| assert lines.any_include?('sleep 12345') }
    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_equal "kill #{pid}", lines[-1] }
  ensure
    if pid
      begin
        Process.kill('KILL', pid.to_i)
      rescue StandardError
        nil
      end
    end
  end

  def test_custom_completion
    tmux.send_keys '_fzf_compgen_path() { echo "$1"; seq 10; }', :Enter
    tmux.prepare
    tmux.send_keys 'ls /tmp/**', :Tab
    tmux.until { |lines| assert_equal 11, lines.match_count }
    tmux.send_keys :Tab, :Tab, :Tab
    tmux.until { |lines| assert_equal 3, lines.select_count }
    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_equal 'ls /tmp 1 2', lines[-1] }
  end

  def test_unset_completion
    tmux.send_keys 'export FZFFOOBAR=BAZ', :Enter
    tmux.prepare

    # Using tmux
    tmux.send_keys 'unset FZFFOOBR**', :Tab
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 'unset FZFFOOBAR', lines[-1] }
    tmux.send_keys 'C-c'

    # FZF_TMUX=1
    new_shell
    tmux.focus
    tmux.send_keys 'unset FZFFOOBR**', :Tab
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal 'unset FZFFOOBAR', lines[-1] }
  end

  def test_completion_in_command_sequence
    tmux.send_keys 'export FZFFOOBAR=BAZ', :Enter
    tmux.prepare

    triggers = ['**', '~~', '++', 'ff', '/']
    triggers.concat(['&', '[', ';', '`']) if instance_of?(TestZsh)

    triggers.each do |trigger|
      set_var('FZF_COMPLETION_TRIGGER', trigger)
      command = "echo foo; QUX=THUD unset FZFFOOBR#{trigger}"
      tmux.send_keys command.sub(/(;|`)$/, '\\\\\1'), :Tab
      tmux.until { |lines| assert_equal 1, lines.match_count }
      tmux.send_keys :Enter
      tmux.until { |lines| assert_equal 'echo foo; QUX=THUD unset FZFFOOBAR', lines[-1] }
    end
  end

  def test_file_completion_unicode
    FileUtils.mkdir_p('/tmp/fzf-test')
    tmux.paste "cd /tmp/fzf-test; echo test3 > $'fzf-unicode \\355\\205\\214\\354\\212\\244\\355\\212\\2701'; echo test4 > $'fzf-unicode \\355\\205\\214\\354\\212\\244\\355\\212\\2702'"
    tmux.prepare
    tmux.send_keys 'cat fzf-unicode**', :Tab
    tmux.until { |lines| assert_equal 2, lines.match_count }

    tmux.send_keys '1'
    tmux.until { |lines| assert_equal 1, lines.match_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 1, lines.select_count }

    tmux.send_keys :BSpace
    tmux.until { |lines| assert_equal 2, lines.match_count }

    tmux.send_keys '2'
    tmux.until { |lines| assert_equal 1, lines.select_count }
    tmux.send_keys :Tab
    tmux.until { |lines| assert_equal 2, lines.select_count }

    tmux.send_keys :Enter
    tmux.until(true) { |lines| assert_match(/cat .*fzf-unicode.*1.* .*fzf-unicode.*2/, lines[-1]) }
    tmux.send_keys :Enter
    tmux.until { |lines| assert_equal %w[test3 test4], lines[-2..] }
  end

  def test_custom_completion_api
    tmux.send_keys 'eval "_fzf$(declare -f _comprun)"', :Enter
    %w[f g].each do |command|
      tmux.prepare
      tmux.send_keys "#{command} b**", :Tab
      tmux.until do |lines|
        assert_equal 2, lines.item_count
        assert_equal 1, lines.match_count
        assert lines.any_include?("prompt-#{command}")
        assert lines.any_include?("preview-#{command}-bar")
      end
      tmux.send_keys :Enter
      tmux.until { |lines| assert_equal "#{command} #{command}barbar", lines[-1] }
      tmux.send_keys 'C-u'
    end
  ensure
    tmux.prepare
    tmux.send_keys 'unset -f _fzf_comprun', :Enter
  end

  def test_ssh_completion
    (1..5).each { |i| FileUtils.touch("/tmp/fzf-test-ssh-#{i}") }

    tmux.send_keys 'ssh jg@localhost**', :Tab
    tmux.until do |lines|
      assert lines.match_count >= 1
    end

    tmux.send_keys :Enter
    tmux.until { |lines| assert lines.any_include?('ssh jg@localhost') }
    tmux.send_keys ' -i /tmp/fzf-test-ssh**', :Tab
    tmux.until do |lines|
      assert lines.match_count >= 5
      assert_equal 0, lines.select_count
    end
    tmux.send_keys :Tab, :Tab, :Tab
    tmux.until do |lines|
      assert_equal 3, lines.select_count
    end
    tmux.send_keys :Enter
    tmux.until { |lines| assert lines.any_include?('ssh jg@localhost  -i /tmp/fzf-test-ssh-') }

    tmux.send_keys 'localhost**', :Tab
    tmux.until do |lines|
      assert lines.match_count >= 1
    end
  end
end

class TestBash < TestBase
  include TestShell
  include CompletionTest

  def shell
    :bash
  end

  def new_shell
    tmux.prepare
    tmux.send_keys "FZF_TMUX=1 #{Shell.bash}", :Enter
    tmux.prepare
  end

  def test_dynamic_completion_loader
    tmux.paste 'touch /tmp/foo; _fzf_completion_loader=1'
    tmux.paste '_completion_loader() { complete -o default fake; }'
    tmux.paste 'complete -F _fzf_path_completion -o default -o bashdefault fake'
    tmux.send_keys 'fake /tmp/foo**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
    tmux.send_keys 'C-c'

    tmux.prepare
    tmux.send_keys 'fake /tmp/foo'
    tmux.send_keys :Tab, 'C-u'

    tmux.prepare
    tmux.send_keys 'fake /tmp/foo**', :Tab
    tmux.until { |lines| assert_operator lines.match_count, :>, 0 }
  end
end

class TestZsh < TestBase
  include TestShell
  include CompletionTest

  def shell
    :zsh
  end

  def new_shell
    tmux.send_keys "FZF_TMUX=1 #{Shell.zsh}", :Enter
    tmux.prepare
  end

  def test_complete_quoted_command
    tmux.send_keys 'export FZFFOOBAR=BAZ', :Enter
    ['unset', '\unset', "'unset'"].each do |command|
      tmux.prepare
      tmux.send_keys "#{command} FZFFOOBR**", :Tab
      tmux.until { |lines| assert_equal 1, lines.match_count }
      tmux.send_keys :Enter
      tmux.until { |lines| assert_equal "#{command} FZFFOOBAR", lines[-1] }
      tmux.send_keys 'C-c'
    end
  end
end

class TestFish < TestBase
  include TestShell

  def shell
    :fish
  end

  def new_shell
    tmux.send_keys 'env FZF_TMUX=1 FZF_DEFAULT_OPTS=--no-scrollbar fish', :Enter
    tmux.send_keys 'function fish_prompt; end; clear', :Enter
    tmux.until { |lines| assert_empty lines }
  end

  def set_var(name, val)
    tmux.prepare
    tmux.send_keys "set -g #{name} '#{val}'", :Enter
    tmux.prepare
  end
end

__END__
set -u
PS1= PROMPT_COMMAND= HISTFILE= HISTSIZE=100
unset <%= UNSETS.join(' ') %>
unset $(env | sed -n /^_fzf_orig/s/=.*//p)
unset $(declare -F | sed -n "/_fzf/s/.*-f //p")

export FZF_DEFAULT_OPTS="--no-scrollbar --pointer '>' --marker '>'"

# Setup fzf
# ---------
if [[ ! "$PATH" == *<%= BASE %>/bin* ]]; then
  export PATH="${PATH:+${PATH}:}<%= BASE %>/bin"
fi

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "<%= BASE %>/shell/completion.<%= __method__ %>" 2> /dev/null

# Key bindings
# ------------
source "<%= BASE %>/shell/key-bindings.<%= __method__ %>"

# Old API
_fzf_complete_f() {
  _fzf_complete "+m --multi --prompt \"prompt-f> \"" "$@" < <(
    echo foo
    echo bar
  )
}

# New API
_fzf_complete_g() {
  _fzf_complete +m --multi --prompt "prompt-g> " -- "$@" < <(
    echo foo
    echo bar
  )
}

_fzf_complete_f_post() {
  awk '{print "f" $0 $0}'
}

_fzf_complete_g_post() {
  awk '{print "g" $0 $0}'
}

[ -n "${BASH-}" ] && complete -F _fzf_complete_f -o default -o bashdefault f
[ -n "${BASH-}" ] && complete -F _fzf_complete_g -o default -o bashdefault g

_comprun() {
  local command=$1
  shift

  case "$command" in
    f) fzf "$@" --preview 'echo preview-f-{}' ;;
    g) fzf "$@" --preview 'echo preview-g-{}' ;;
    *) fzf "$@" ;;
  esac
}
