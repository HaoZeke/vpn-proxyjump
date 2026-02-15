;;; publish.el --- Export readme.org to HTML with Sakura CSS  -*- lexical-binding: t; -*-

(require 'ox-html)

(setq org-html-head
      (concat
       "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css\" media=\"screen\" />\n"
       "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/sakura.css/css/sakura-dark.css\" media=\"screen and (prefers-color-scheme: dark)\" />\n"
       "<style>body { max-width: 50em; } pre { overflow-x: auto; }</style>\n"))

(setq org-html-head-include-default-style nil)
(setq org-html-head-include-scripts nil)
(setq org-html-validation-link nil)
(setq org-html-postamble nil)
(setq org-html-htmlize-output-type nil)

(with-current-buffer (find-file-noselect "readme.org")
  (org-html-export-to-html))
