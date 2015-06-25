;;; funcs.el --- Scala Layer functions File for Spacemacs
;;
;; Copyright (c) 2012-2014 Sylvain Benner
;; Copyright (c) 2014-2015 Sylvain Benner & Contributors
;;
;; Author: Sylvain Benner <sylvain.benner@gmail.com>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3

;;; Ensime

(autoload 'ensime-config-find-file "ensime-config")
(autoload 'ensime-config-find "ensime-config")
(autoload 'projectile-project-p "projectile")

(defun scala/configure-ensime ()
  "Ensure the file exists before starting `ensime-mode'."
  (cond
   ((and (buffer-file-name) (file-exists-p (buffer-file-name)))
    (ensime-mode +1))
   ((buffer-file-name)
    (add-hook 'after-save-hook (lambda () (ensime-mode +1)) nil t))))

(defun scala/maybe-start-ensime ()
  (when (buffer-file-name)
    (let ((ensime-buffer (scala/ensime-buffer-for-file (buffer-file-name)))
          (file (ensime-config-find-file (buffer-file-name)))
          (is-source-file (s-matches? (rx (or "/src/" "/test/")) (buffer-file-name))))

      (when (and is-source-file (null ensime-buffer))
        (noflet ((ensime-config-find (&rest _) file))
          (save-window-excursion
            (ensime)))))))

(defun scala/ensime-buffer-for-file (file)
  "Find the Ensime server buffer corresponding to FILE."
  (let ((default-directory (file-name-directory file)))
    (-when-let (project-name (projectile-project-p))
      (--first (-when-let (bufname (buffer-name it))
                 (and (s-contains? "inferior-ensime-server" bufname)
                      (s-contains? (file-name-nondirectory project-name) bufname)))
               (buffer-list)))))

(defun scala/enable-eldoc ()
  (setq-local eldoc-documentation-function
              (lambda ()
                (when (ensime-connected-p)
                  (ensime-print-type-at-point))))
  (eldoc-mode +1))

(defun spacemacs/ensime-refactor-accept ()
  (interactive)
  (funcall continue-refactor)
  (ensime-popup-buffer-quit-function))

(defun spacemacs/ensime-refactor-cancel ()
  (interactive)
  (funcall cancel-refactor)
  (ensime-popup-buffer-quit-function))

;;; Interactive commands

(defun spacemacs/scala-join-line ()
  "Adapt `scala-indent:join-line' to behave more like evil's line join.

`scala-indent:join-line' acts like the vanilla `join-line',
joining the current line with the previous one. The vimmy way is
to join the current line with the next.

Try to move to the subsequent line and then join. Then manually move
point to the position of the join."
  (interactive)
  (let (join-pos)
    (save-excursion
      (goto-char (line-end-position))
      (unless (eobp)
        (forward-line)
        (call-interactively 'scala-indent:join-line)
        (setq join-pos (point))))

    (when join-pos
      (goto-char join-pos))))

(defun scala/completing-dot ()
  "Insert a period and show company completions."
  (interactive "*")
  (when (s-matches? (rx (+ (not space)))
                    (buffer-substring (line-beginning-position) (point)))
    (delete-horizontal-space t))

  (cond (company-backend
         (company-complete-selection)
         (scala/completing-dot))

        (t
         (insert ".")
         (company-complete))))

;;; Flyspell

(defun scala/flyspell-verify ()
  "Prevent common flyspell false positives in scala-mode."
  (and (flyspell-generic-progmode-verify)
       (not (s-matches? (rx bol (* space) "package") (current-line)))))

(defun scala/configure-flyspell ()
  (setq-local flyspell-generic-check-word-predicate 'scala/flyspell-verify))

;;; Spark

(defun scala/spark-submit ()
  "Submit the current project to Spark."
  (interactive "")
  (progn
    (cd (projectile-project-root))
    (if (get-buffer "*spark*") (kill-buffer "*spark*"))
    (call-process "ag" nil "*spark*" nil "-l" "-s" "main" "src")
    (switch-to-buffer "*spark*")
    (let* ((ag-out (buffer-string))
           (class-file (substring ag-out (+ 1 (string-match "\\/\\w+\\.scala" ag-out))))
           (class-name (substring class-file 0 (string-match "\\.scala" class-file))))
      (kill-buffer)
      (call-process "/bin/bash" nil "*spark*" nil "-c" "ls target/scala-*/*.jar")
      (switch-to-buffer "*spark*")
      (let ((jar-file (substring (buffer-string) 0 -1)))
        (kill-buffer)
        (if (get-buffer "*Spark*") (kill-buffer "*Spark*"))
        (start-process "spark-submit" "*Spark*" "spark-submit"
                       "--class" class-name
                       "--master" "local[4]"
                       jar-file)
        (display-buffer "*Spark*")
        (with-selected-window (get-buffer-window "*Spark*")
          (goto-char (point-max)))
        ))
    ))
