;;; tree-sitter-tests.el --- Tests for tree-sitter.el -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2019  Tuấn-Anh Nguyễn
;;
;; Author: Tuấn-Anh Nguyễn <ubolonton@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; Tests for `tree-sitter'.

;;; Code:

(require 'tree-sitter)
(require 'tree-sitter-debug)

(defvar tree-sitter-langs--testing)
;;; Disable grammar downloading.
(let ((tree-sitter-langs--testing t))
  (require 'tree-sitter-langs))
;;; Build the grammars, if necessary.
(dolist (lang-symbol '(rust python javascript c))
  (tree-sitter-langs-ensure lang-symbol))

;; XXX: Bash grammar failed 'tree-sitter test' on Windows: 'Escaped newlines'.
(with-demoted-errors "Failed to ensure bash grammar %s"
  (tree-sitter-langs-ensure 'bash))

(require 'ert)

(eval-when-compile
  (require 'subr-x)
  (require 'cl-lib))

;;; ----------------------------------------------------------------------------
;;; Helpers.

(defun tsc-test-make-parser (lang-symbol)
  "Return a new parser for LANG-SYMBOL."
  (let ((parser (tsc-make-parser))
        (language (tree-sitter-require lang-symbol)))
    (tsc-set-language parser language)
    parser))

(defun tsc-test-full-path (relative-path)
  "Return full path from project RELATIVE-PATH."
  (concat (file-name-directory
           (directory-file-name
            (file-name-directory (locate-library "tree-sitter.el")))) relative-path))

(defun tsc-test-tree-sexp (sexp &optional reset)
  "Check that the current syntax tree's sexp representation is SEXP.
If RESET is non-nil, also do another full parse and check again."
  (should (equal (read (tsc-tree-to-sexp tree-sitter-tree)) sexp))
  (when reset
    (setq tree-sitter-tree nil)
    (tree-sitter--do-parse)
    (tsc-test-tree-sexp sexp)))

(defun tsc-test-use-lang (lang-symbol)
  "Turn on `tree-sitter-mode' in the current buffer, using language LANG-SYMBOL."
  (setq tree-sitter-language (tree-sitter-require lang-symbol))
  (ignore-errors
    (setq tree-sitter-hl-default-patterns
          (tree-sitter-langs--hl-default-patterns lang-symbol)))
  (add-hook 'tree-sitter-after-first-parse-hook
            (lambda () (should (not (null tree-sitter-tree)))))
  (tree-sitter-mode))

(defmacro tsc-test-with (lang-symbol var &rest body)
  "Eval BODY with VAR bound to a new parser for LANG-SYMBOL."
  (declare (indent 2))
  `(let ((,var (tsc-test-make-parser ,lang-symbol)))
     ,@body))

(defmacro tsc-test-with-file (relative-path &rest body)
  "Eval BODY in a temp buffer filled with content of the file at RELATIVE-PATH."
  (declare (indent 1))
  `(with-temp-buffer
     (let ((coding-system-for-read 'utf-8))
       (insert-file-contents (tsc-test-full-path ,relative-path)))
     ,@body))

(defmacro tsc-test-lang-with-file (lang-symbol relative-path &rest body)
  "Eval BODY in a temp buffer filled with content of the file at RELATIVE-PATH.
`tree-sitter-mode' is turned on, using the given language LANG-SYMBOL."
  (declare (indent 2))
  `(tsc-test-with-file ,relative-path
     (tsc-test-use-lang ,lang-symbol)
     ,@body))

(defmacro tsc-test-with-advice (symbol where function &rest body)
  "Eval BODY while advising SYMBOL with FUNCTION at WHERE."
  (declare (indent 3))
  `(progn
     (advice-add ,symbol ,where ,function)
     (unwind-protect
         ,@body
       (advice-remove ,symbol ,function))))

;;; ----------------------------------------------------------------------------
;;; Tests.

(ert-deftest creating-parser ()
  (should (tsc-parser-p (tsc-test-make-parser 'rust))))

(ert-deftest language::info ()
  (dolist (lang-symbol '(rust bash javascript c))
    (let ((language (tree-sitter-require lang-symbol)))
      (should (eq lang-symbol (tsc--lang-symbol language))))))

(ert-deftest language::equality ()
  (tsc-test-with 'rust parser
    ;; XXX: `equal' seems to return nil even if 2 `user-ptr' objects have the same pointer and
    ;; finalizer. That's broken. Report a bug to emacs-devel.
    (should (equal (format "%s" (tsc-parser-language parser))
                   (format "%s" (tree-sitter-require 'rust))))))

(ert-deftest language::node-types ()
  (let* ((language (tree-sitter-require 'rust))
         (type-count (tsc-lang-count-types language)))
    (ert-info ("Round tripping node-type node-type-id")
      (dolist (node-type '(identifier function_item "if" "else"))
        (should (equal (thread-last node-type
                         (tsc-lang-node-type-id language)
                         (tsc-lang-node-type language))
                       node-type))))
    (ert-info ("0 should be the special node type \"end\"")
      (should (equal :end (tsc-lang-node-type language 0))))
    (ert-info ("Node type IDs should be from 0 to type count minus 1")
      (should-not (null (tsc-lang-node-type language 1)))
      (should-not (null (tsc-lang-node-type language (- type-count 1))))
      (should (null (tsc-lang-node-type language type-count))))))

(ert-deftest language::fields ()
  (let* ((language (tree-sitter-require 'rust))
         (field-count (tsc-lang-count-fields language)))
    (ert-info ("Round tripping field field-id")
      (dolist (field '(:name :left :right :value))
        (should (eq (thread-last field
                      (tsc-lang-field-id language)
                      (tsc-lang-field language))
                    field))))
    (ert-info ("Field IDs should be from 1 to field count")
      (should (null (tsc-lang-field language 0)))
      (should (keywordp (tsc-lang-field language 1)))
      (should (keywordp (tsc-lang-field language field-count)))
      (should (null (tsc-lang-field language (1+ field-count)))))))

(ert-deftest parsing::rust-string ()
  (tsc-test-with 'rust parser
    (let ((tree (tsc-parse-string parser "fn foo() {}")))
      (should (equal (read (tsc-tree-to-sexp tree))
                     '(source_file
                       (function_item
                        name: (identifier)
                        parameters: (parameters)
                        body: (block))))))))

(ert-deftest parsing::without-setting-language ()
  (ert-skip "Need to distinguish between this and timeout/cancellation")
  (let ((parser (tsc-make-parser)))
    (should-error (tsc-parse-string parser "fn foo() {}") :type 'rust-panic)))

(ert-deftest parsing::rust-buffer ()
  (tsc-test-with 'rust parser
    (tsc-test-with-file "lisp/test-files/types.rs"
      (tsc--without-restriction
        (let* ((tree) (old-tree)
               (initial (benchmark-run
                            (setq tree (tsc-parse-chunks parser #'tsc--buffer-input nil))))
               (reparse (benchmark-run
                            (progn
                              (setq old-tree tree)
                              (setq tree (tsc-parse-chunks parser #'tsc--buffer-input old-tree))))))
          (ert-info ("Same code should result in empty change ranges")
            (should (equal [] (tsc-changed-ranges old-tree tree))))
          (ert-info ("Incremental parsing should be faster than initial")
            (should (> (car initial) (car reparse)))))))))

(ert-deftest minor-mode::basic-editing ()
  (with-temp-buffer
    (tsc-test-use-lang 'rust)
    (tsc-test-tree-sexp '(source_file))
    (insert "fn")
    (tsc-test-tree-sexp '(source_file (ERROR)))
    (insert " foo() {}")
    (tsc-test-tree-sexp '(source_file
                         (function_item
                          name: (identifier)
                          parameters: (parameters)
                          body: (block))))
    (kill-region (point-min) (point-max))
    (tsc-test-tree-sexp '(source_file))))

(ert-deftest minor-mode::incremental:change-case-region ()
  (cl-flet ((assert-same-range
             (_tree _beg-byte old-end-byte new-end-byte
                    _beg-point old-end-point new-end-point &rest _)
             (should (= old-end-byte new-end-byte))
             (should (equal old-end-point new-end-point))))
    (tsc-test-lang-with-file 'rust "lisp/test-files/change-case-region.rs"
      (tsc-test-with-advice 'tsc-edit-tree :before #'assert-same-range
        (let* ((orig-sexp (read (tsc-tree-to-sexp tree-sitter-tree)))
               (end (re-search-forward "this text"))
               (beg (match-beginning 0)))
          (upcase-initials-region beg end)
          (tsc-test-tree-sexp orig-sexp)
          (upcase-region beg end)
          (tsc-test-tree-sexp orig-sexp)
          (downcase-region beg end)
          (tsc-test-tree-sexp orig-sexp :reset))))))

(ert-deftest minor-mode::incremental:delete-non-ascii-text ()
  (tsc-test-lang-with-file 'rust "lisp/test-files/delete-non-ascii-text.rs"
    (let* ((orig-sexp (read (tsc-tree-to-sexp tree-sitter-tree)))
           (end (re-search-forward "ấấấấấấấấ"))
           (beg (match-beginning 0)))
      (delete-region beg end)
      (tsc-test-tree-sexp orig-sexp :reset))))

(ert-deftest minor-mode::node-at-point ()
  (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
    (should (eq 'source_file (tsc-node-type (tree-sitter-node-at-point 'source_file))))
    (search-forward "erase_")
    (should (eq 'identifier (tsc-node-type (tree-sitter-node-at-point))))
    (should (eq 'function_item (tsc-node-type (tree-sitter-node-at-point 'function_item))))
    (should (null (tree-sitter-node-at-point "function_item")))
    (should (null (tree-sitter-node-at-point 'impl_item)))
    ;; FIX: Signal an error for non-existing node types.
    (should (null (tree-sitter-node-at-point 'non-existing-node-type)))
    (search-forward "struc")
    (should (equal "struct" (tsc-node-type (tree-sitter-node-at-point))))
    (should (eq 'struct_item (tsc-node-type (tree-sitter-node-at-point 'struct_item))))))

(ert-deftest node::eq ()
  (tsc-test-with 'rust parser
    (let* ((tree (tsc-parse-string parser "fn foo() {}"))
           (node1 (tsc-root-node tree))
           (node2 (tsc-root-node tree)))
      (should (tsc-node-eq node1 node2))
      (should-not (tsc-node-eq node1 (tsc-get-nth-child node1 0))))))

(ert-deftest node::using-without-tree ()
  "Test that a tree's nodes are still usable after no direct reference to the
tree is held (since nodes internally reference the tree)."
  (tsc-test-with 'rust parser
    (let ((node (tsc-root-node
                 (tsc-parse-string parser "fn foo() {}"))))
      (garbage-collect)
      (should (eql 1 (tsc-count-children node))))
    (garbage-collect)))

(ert-deftest node::types ()
  (tsc-test-with 'rust parser
    (ert-info ("Error nodes")
      (let* ((root (tsc-root-node (tsc-parse-string parser "fn")))
             (err (tsc-get-nth-child root 0)))
        (should (tsc-node-has-error-p root))
        (should-not (tsc-node-error-p root))
        (should (eq (tsc-node-type root) 'source_file))
        (ert-info ("Should have a special type")
          (should (eq (tsc-node-type err) 'ERROR)))
        (should (tsc-node-error-p err))
        (should (tsc-node-has-error-p err))))
    (ert-info ("Missing nodes")
      (let* ((root (tsc-root-node (tsc-parse-string parser "let x = 1")))
             (decl (tsc-get-nth-child root 0))
             (n (tsc-count-children decl))
             (semi (tsc-get-nth-child decl (- n 1))))
        (should (tsc-node-has-error-p root))
        (should-not (tsc-node-error-p root))
        (should (eq (tsc-node-type root) 'source_file))
        (ert-info ("Should have a normal type")
          (should (equal (tsc-node-type semi) ";")))
        (should (tsc-node-missing-p semi))))))

(ert-deftest cursor::walk ()
  (tsc-test-with 'rust parser
    (let* ((tree (tsc-parse-string parser "fn foo() {}"))
           (node (tsc-root-node tree)))
      (ert-info ("Should be able to get a cursor from either a tree or a node")
        (should (tsc-cursor-p (tsc-make-cursor tree)))
        (should (tsc-cursor-p (tsc-make-cursor node)))))))

(ert-deftest cursor::reset ()
  (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
    (let* ((node (tsc-root-node tree-sitter-tree))
           (cursor (tsc-make-cursor node)))
      (tsc-goto-first-child cursor)
      (should-not (equal (tsc-node-type (tsc-current-node cursor)) 'source_file))
      (tsc-reset-cursor cursor node)
      (should (equal (tsc-node-type (tsc-current-node cursor)) 'source_file)))))

(ert-deftest cursor::using-without-tree ()
  (tsc-test-with 'rust parser
    (let ((cursor (tsc-make-cursor (tsc-parse-string parser "fn foo() {}"))))
      (garbage-collect)
      (should (tsc-goto-first-child cursor)))
    (garbage-collect)))

(ert-deftest conversion::position<->tsc-point ()
  (tsc-test-with-file "lisp/tree-sitter-tests.el"
    (ert-info ("Testing buffer boundaries")
      (let ((min (point-min))
            (max (point-max)))
        (should (equal '(1 . 0) (tsc-point-from-position min)))
        (should (= min (tsc-point-to-position (tsc-point-from-position min))))
        (should (= max (tsc-point-to-position (tsc-point-from-position max))))))
    (ert-info ("Testing arbitrary points")
      (dotimes (_ 100)
        (let ((p (1+ (random (buffer-size)))))
          (should (= p (tsc-point-to-position (tsc-point-from-position p)))))))))

(ert-deftest buffer-input::non-ascii-characters ()
  (with-temp-buffer
    (insert "\"Tuấn-Anh Nguyễn\";")
    (tsc-test-use-lang 'javascript)
    (tsc-test-tree-sexp '(program (expression_statement (string))))))

;; https://github.com/ubolonton/emacs-tree-sitter/issues/3
(ert-deftest buffer-input::narrowing ()
  (tsc-test-with-file "bin/build"
    (sh-mode)
    (tree-sitter-mode)
    (call-interactively #'mark-whole-buffer)
    (call-interactively #'comment-or-uncomment-region)))

(ert-deftest query::making ()
  (let ((rust (tree-sitter-require 'rust)))
    (ert-info ("Should work on string")
      (should (= (tsc-query-count-patterns
                  (tsc-make-query rust "(function_item (identifier) @function)
                                       (macro_definition (identifier) @macro)"))
                 2)))
    (ert-info ("Should work on vector")
      (should (= (tsc-query-count-patterns
                  (tsc-make-query rust [(function_item (identifier) @function)
                                       (macro_definition (identifier) @macro)]))
                 2)))))

(ert-deftest query::basic ()
  (tsc-test-lang-with-file 'rust "core/src/query.rs"
    ;; This is to make sure it works correctly with narrowing.
    (narrow-to-region 1 2)
    (let* ((captures (tree-sitter-debug-query
                      "((function_item (identifier) @function)
                        (match? @function \"make_query\"))
                       (macro_definition (identifier) @macro)"))
           (node-texts (mapcar (lambda (capture)
                                 (pcase-let ((`(_ . ,node) capture))
                                   (tsc-node-text node)))
                               captures))
           (capture-tags (mapcar (lambda (capture)
                                    (pcase-let ((`(,tag . _) capture)) tag))
                                  captures)))
      (ert-info ("Should match specified functions and not more")
        (should (member "_make_query" node-texts))
        (should (member "make_query_cursor" node-texts))
        (should (not (member "capture_names" node-texts))))
      (ert-info ("Should capture some macros")
        (should (member 'macro capture-tags))))))

(ert-deftest query::range-restriction ()
  ;; https://github.com/tree-sitter/tree-sitter/issues/685
  (tsc-test-lang-with-file 'c "lisp/test-files/range-restriction-and-early-termination.c"
    (let ((cursor (tsc-make-query-cursor))
          (query (tsc-make-query tree-sitter-language
                                [(call_expression
                                  function: (identifier) @function
                                  arguments: (argument_list (string_literal) @string.arg))
                                 (string_literal) @string]))
          (root-node (tsc-root-node tree-sitter-tree))
          (capture-names '(function string.arg string)))
      (ert-info ("Querying without range restriction")
        (should (equal (mapcar #'car (tsc-query-captures
                                      query root-node #'tsc--buffer-substring-no-properties cursor))
                       capture-names))
        (should (equal (mapcar #'car (tsc--query-cursor-captures-1
                                      cursor query root-node #'tsc--buffer-substring-no-properties))
                       capture-names)))
      (ert-info ("Querying with range restriction")
        (tsc--query-cursor-set-byte-range cursor 1 28)
        (should (equal (mapcar #'car (tsc-query-captures
                                      query root-node #'tsc--buffer-substring-no-properties cursor))
                       capture-names))
        (should (equal (mapcar #'car (tsc--query-cursor-captures-1
                                      cursor query root-node #'tsc--buffer-substring-no-properties))
                       capture-names))))))

(ert-deftest query::validation ()
  ;; https://github.com/ubolonton/emacs-tree-sitter/issues/125
  (should (tsc-make-query (tree-sitter-require 'rust)
                          [(unary_expression (identifier)* @variable)])))

(ert-deftest load ()
  (should-error (tree-sitter-require 'abc-xyz))
  (tree-sitter-require 'rust))

;;; ----------------------------------------------------------------------------
;;; Highlighting tests.

(ert-deftest hl::extend-region ()
  (tsc-test-lang-with-file 'rust "lisp/test-files/extend-region.rs"
    (tree-sitter-hl-mode)
    (let* ((beg (save-excursion
                  (re-search-forward "^abc")
                  (backward-char)
                  (point)))
           (end (1+ beg)))
      (tree-sitter-hl--highlight-region beg end)
      (ert-info ("Highlighting a tiny region")
        (should (memq 'tree-sitter-hl-face:function.macro
                      (get-text-property beg 'face)))))))

(ert-deftest hl::hl-region-vs-query-region ()
  (tsc-test-lang-with-file 'javascript "lisp/test-files/hl-region-vs-query-region.js"
    (tree-sitter-hl-mode)
    (let ((tree-sitter-hl--extend-region-limit 16)
          id-end id-beg)
      (save-excursion
        (search-forward "compound_assignment_expr:")
        (backward-char)
        (setq id-end (point))
        (search-backward "compound_assignment_expr")
        (setq id-beg (point)))
      (tree-sitter-hl--highlight-region 1 id-end)
      (ert-info ("Highlighting a region that cuts a pattern in halves")
        (should (memq 'tree-sitter-hl-face:property.definition
                      (get-text-property id-beg 'face)))
        (should (eq (next-single-property-change id-beg 'face)
                    id-end))))))

(ert-deftest hl::face-mapping ()
  (ert-skip "WIP")
  (ert-info ("Keywords should not be highlighted if their capture name is disabled")
    (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
      ;; Disable keyword highlighting.
      (add-function :before-while (local 'tree-sitter-hl-face-mapping-function)
                    (lambda (capture-name)
                      (not (string= capture-name "keyword"))))
      (tree-sitter-hl-mode)
      (font-lock-ensure)
      (should (null (get-text-property 1 'face)))
      (ert-info ("Other elements should still be highlighted")
        (should-not (null (next-single-property-change 1 'face))))))
  (ert-info ("Keywords should be highlighted by default")
    (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
      (tree-sitter-hl-mode)
      (font-lock-ensure)
      (should (memq 'tree-sitter-hl-face:keyword (get-text-property 1 'face)))))
  (ert-info ("Keywords should not be highlighted if their capture name is disabled")
    (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
      ;; Disable keyword highlighting.
      (add-function :before-while (local 'tree-sitter-hl-face-mapping-function)
                    (lambda (capture-name)
                      (not (string= capture-name "keyword"))))
      (tree-sitter-hl-mode)
      (font-lock-ensure)
      (should (null (get-text-property 1 'face)))
      (ert-info ("Other elements should still be highlighted")
        (should-not (null (next-single-property-change 1 'face))))))
  (ert-info ("Nothing should be highlighted if all capture names are disabled")
    (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
      (add-function :override (local 'tree-sitter-hl-face-mapping-function)
                    (lambda (capture-name) nil))
      (tree-sitter-hl-mode)
      (font-lock-ensure)
      (ert-info ("`face' should be nil for the whole buffer")
        (should (null (get-text-property 1 'face)))
        (should (null (next-single-property-change 1 'face)))))))

(ert-deftest hl::with-font-lock-mode-disabled ()
  ;; https://github.com/ubolonton/emacs-tree-sitter/issues/74
  (with-current-buffer (find-file (tsc-test-full-path "lisp/test-files/hl.py"))
    (tree-sitter-hl-mode)
    (font-lock-mode -1)
    (font-lock-ensure)
    (should (memq 'tree-sitter-hl-face:function (get-text-property 6 'face)))))

(ert-deftest hl::bench ()
  (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
    (setq tree-sitter-hl-default-patterns (tree-sitter-langs--hl-default-patterns 'rust))
    (require 'rust-mode)
    (rust-mode)
    (font-lock-mode)
    (font-lock-set-defaults)
    (tree-sitter-hl-mode)
    (garbage-collect)
    (message "tree-sitter-hl  1 %s" (benchmark-run (font-lock-ensure)))
    (garbage-collect)
    (message "tree-sitter-hl 10 %s" (benchmark-run 10 (font-lock-ensure)))
    (tree-sitter-hl-mode -1)

    (font-lock-ensure)
    (garbage-collect)
    (message "     font-lock  1 %s" (benchmark-run (font-lock-ensure)))
    (garbage-collect)
    (message "     font-lock 10 %s" (benchmark-run 10 (font-lock-ensure)))

    (let ((tree-sitter-hl--direct-buffer-access t))
      (tree-sitter-hl-mode)
      (garbage-collect)
      (message " direct-access  1 %s" (benchmark-run (font-lock-ensure)))
      (garbage-collect)
      (message " direct-access 10 %s" (benchmark-run 10 (font-lock-ensure)))
      (tree-sitter-hl-mode -1))))

(ert-deftest debug::jump ()
  "Test if the first button takes us to the beginning of the file.
We know it should since it is the `source_file' node."
  (tsc-test-lang-with-file 'rust "lisp/test-files/types.rs"
    (let ((buf-name (buffer-name)))
    (setq tree-sitter-debug-jump-buttons t)
    (tree-sitter-debug-mode)
    (goto-char (point-max))
    (should (> (point) 0)) ; Test if worthless if the file is empty
    (switch-to-buffer tree-sitter-debug--tree-buffer nil t)
    (tree-sitter-debug--button-node-lookup (button-at 1))
    (should (= (point) (point-min))))))

;; Local Variables:
;; no-byte-compile: t
;; End:

(provide 'tree-sitter-tests)
;;; tree-sitter-tests.el ends here
