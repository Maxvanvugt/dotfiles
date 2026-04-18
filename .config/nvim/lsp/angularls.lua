-- Requires `ngserver` on PATH (e.g. npm i -g @angular/language-server).
return {
	cmd = { "ngserver", "--stdio" },
	filetypes = { "html", "typescript", "typescriptreact", "htmlangular" },
	root_markers = { "angular.json", "nx.json", "project.json", ".git" },
}
