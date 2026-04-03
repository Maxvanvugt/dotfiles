-- Requires `ngserver` on PATH (e.g. npm i -g @angular/language-server).
return {
	cmd = { "ngserver", "--stdio" },
	filetypes = { "html", "typescript", "typescriptreact" },
	root_markers = { "angular.json", "nx.json", "project.json", ".git" },
}
