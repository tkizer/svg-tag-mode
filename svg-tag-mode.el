;;; svg-tag-mode.el --- Replace keywords with SVG tags -*- lexical-binding: t -*-

;; Copyright (C) 2020, 2021 Nicolas P. Rougier

;; Author: Nicolas P. Rougier <Nicolas.Rougier@inria.fr>
;; Homepage: https://github.com/rougier/svg-tag-mode
;; Keywords: convenience
;; Version: 0.3

;; Package-Requires: ((emacs "27.1") (svg-lib "0.3"))

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This minor mode replaces keywords or expressions with SVG tags
;; that are fully customizable and activable.
;;
;; Usage example:
;; --------------
;;
;; (setq svg-tag-tags '((":TODO:"  ((svg-tag-make "TODO") nil nil))))
;;
;; Each item has the form '(KEYWORD (TAG COMMAND HELP)) where:
;;  - KEYWORD is a regular expression including a matched group of 
;;    the form "\\(xxx\\)". If this is not the case the whole
;;    string will be used a the matched group.
;;  - TAG is either a SVG image that will be displayed using the
;;    'display property or a function that accepts a unique string
;;    argument (match-string 1) and returns an SVG image.
;;  - COMMAND is a command to be executed when user clicks on the tag.
;;    It can be nil if no command is associated with the tag.
;;  - HELP is a string to be displayed when mouse pointer is over
;;    the tag. It can be nil if no command is associated with the tag.
;;
;;
;; Examples:
;; ---------
;;
;; ;; This replaces any occurence of ":TODO:" with a static SVG tag
;; ;; displaying "TODO"
;; (setq svg-tag-tags
;;       '((":TODO:" . ((svg-tag-make "TODO")))))
;;
;; ;; This replaces any occurence of ":HELLO:" with a static SVG tag that
;; ;; can be clicked to execute the specified command. Help message is
;; ;; displayed when the tag is hovered with the pointer.
;; (setq svg-tag-tags
;;       '((":HELLO:" .  ((svg-tag-make "HELLO")
;;                        (lambda () (interactive) (message "Hello world!"))
;;                        "Print a greeting message"))))
;;
;; ;; This replaces any occurence of ":TODO:" with a dynamic SVG tag
;; ;; displaying ":TODO:"
;; (setq svg-tag-tags
;;       '((":TODO:" . (svg-tag-make))))
;;
;; ;; This replaces any occurence of ":TODO:" with a dynamic SVG tag
;; ;; displaying "TODO"
;; (setq svg-tag-tags
;;       '((":TODO:" . ((lambda (tag)
;;                        (svg-tag-make tag :beg 1 :end -1))))))
;;
;; ;; This replaces any occurence of ":XXX:" with a dynamic SVG tag
;; ;; displaying "XXX"
;; (setq svg-tag-tags
;;       '(("\\(:[A-Z]+:\\)" . ((lambda (tag)
;;                                (svg-tag-make tag :beg 1 :end -1))))))
;;
;; ;; This replaces any occurence of ":XXX|YYY:" with two adjacent
;; ;; dynamic SVG tags displaying "XXX" and "YYY"
;; (setq svg-tag-tags
;;       '(("\\(:[A-Z]+\\)\|[a-zA-Z#0-9]+:" . ((lambda (tag)
;;                                            (svg-tag-make tag :beg 1 :inverse t
;;                                                           :margin 0 :crop-right t))))
;;         (":[A-Z]+\\(\|[a-zA-Z#0-9]+:\\)" . ((lambda (tag)
;;                                            (svg-tag-make tag :beg 1 :end -1
;;                                                          :margin 0 :crop-left t))))))
;;
;; ;; This replaces any occurence of ":#TAG1:#TAG2:…:$" ($ means end of
;; ;; line) with a dynamic collection of SVG tags. Note the # symbol in
;; ;; front of tags. This is mandatory because Emacs cannot do regex look
;; ;; ahead.
;; (setq svg-tag-tags
;;       '(("\\(:#[A-Za-z0-9]+\\)" . ((lambda (tag)
;;                                      (svg-tag-make tag :beg 2))))
;;         ("\\(:#[A-Za-z0-9]+:\\)$" . ((lambda (tag)
;;                                        (svg-tag-make tag :beg 2 :end -1))))))
;;
;;; NEWS:
;;
;; Version 0.3:
;; - Tags are now editable when cursor is inside.
;;
;; Version 0.2:
;; - Added activable tags
;; - svg-lib dependency
;;
;; Version 0.1:
;; - Proof of concept
;;

;;; Code:
(require 'svg-lib)

(defvar svg-tag--active-tags nil
  "Set of currently active tags")

(defgroup svg-tag nil
  "Replace keywords with SVG rounded box labels"
  :group 'convenience
  :prefix "svg-tag-")

(defcustom svg-tag-action-at-point 'echo
  "Action to be executed when the cursor enter a tag area"
  :type '(radio (const :tag "Edit tag"  edit)
                (const :tag "Echo tag"  echo)
                (const :tag "No action" nil))
  :group 'svg-tag)

(defun svg-tag--plist-delete (plist property)
  "Delete PROPERTY from PLIST.
This is in contrast to merely setting it to 0."
  (let (p)
    (while plist
      (if (not (eq property (car plist)))
	  (setq p (plist-put p (car plist) (nth 1 plist))))
      (setq plist (cddr plist)))
    p))

(defcustom svg-tag-tags
  `(("^TODO" . ((svg-tag-make "TODO") nil nil)))
  "An alist mapping keywords to tags used to display them.

Each entry has the form (keyword . tag).  Keyword is used as part
of a regular expression and tag can be either a svg tag
previously created by `svg-tag-make' or a function that takes a
string as argument and returns a tag.  When tag is a function, this
allows to create dynamic tags."
  :group 'svg-tag
  :type '(repeat (cons (string :tag "Keyword")
                       (list (sexp     :tag "Tag")
                             (sexp     :tag "Command")
                             (sexp     :tag "Help")))))

(defun svg-tag-make (tag &optional &rest args)
  "Return a svg tag displaying TAG and using specified ARGS.
   
  ARGS are passed to the `svg-lib-tag' function but there are
  supplementary arguments:

  :beg (integer) specifies the first index of the tag substring to
                 take into account (default 0)

  :end (integer) specifies the last index of the tag substring to
                 take into account (default nil)

  :face (face) indicates the face to use to compute foreground &
               background color (default 'default)

  :inverse (bool) indicates whether to inverse foreground &
                  background color (default nil)

   Note that :foreground, :background, :stroke and :font-weight
   cannot be specified because thay are overwritten by the
   function. If you need full control of tag appearance, best is
   to call svg-lib-tag directly."
  
  (let* ((face (or (plist-get args :face) 'default))
         (inverse (or (plist-get args :inverse) nil))
         (tag (string-trim tag))
         (beg (or (plist-get args :beg) 0))
         (end (or (plist-get args :end) nil))
         (args (svg-tag--plist-delete args 'stroke))
         (args (svg-tag--plist-delete args 'foreground))
         (args (svg-tag--plist-delete args 'background))
         (args (svg-tag--plist-delete args 'font-weight)))
    (if inverse
        (apply #'svg-lib-tag (substring tag beg end) nil
               :stroke 0
               :font-weight 'semibold
               :foreground (face-background face nil 'default)
               :background (face-foreground face nil 'default)
               args)
      (apply #'svg-lib-tag (substring tag beg end) nil
                   :stroke 2
                   :font-weight 'regular
                   :foreground (face-foreground face nil 'default)
                   :background (face-background face nil 'default)
                   args))))

(defun svg-tag--cursor-function (win position direction)
  "This function hides the tag when cursor is over it, allowing
 to edit it."
  (let ((beg (if (eq direction 'entered)
                 (previous-property-change (+ (point) 1))
               (previous-property-change (+ position 1))))
        (end (if (eq direction 'entered)
                 (next-property-change (point))
               (next-property-change position))))

    (if (eq svg-tag-action-at-point 'edit)
        (if (eq direction 'left)
            (font-lock-flush beg end )
          (if (and (not view-read-only) (not buffer-read-only))
              (font-lock-unfontify-region beg end))))
    
    (if (eq svg-tag-action-at-point 'echo)
        (if (eq direction 'entered)
            (let ((message-log-max nil))
              (message (concat "TAG: "
                               (substring-no-properties
                                (string-trim
                                 (buffer-substring beg end ))))))))))

(defun svg-tag--build-keywords (item)
  "Process an item in order to install it as a new keyword."
    
  (let* ((pattern  (if (string-match "\\\\(.+\\\\)" (car item))
                       (car item)
                     (format "\\(%s\\)" (car item))))
         (tag      (nth 0 (cdr item)))
         (callback (nth 1 (cdr item)))
         (help     (nth 2 (cdr item))))
    (when (or (functionp tag) (and (symbolp tag) (fboundp tag)))
      (setq tag `(,tag (match-string 1))))
    (setq tag ``(face nil
                 display ,,tag
                 cursor-sensor-functions ,'(svg-tag--cursor-function)
                 cursor-sensor-functions (svg-tag--cursor-function)
                 ,@(if ,callback '(pointer hand))
                 ,@(if ,help `(help-echo ,,help))
                 ,@(if ,callback `(keymap (keymap (mouse-1  . ,,callback))))))
    `(,pattern 1 ,tag)))

(defun svg-tag--remove-text-properties (oldfun start end props  &rest args)
  "This applies remove-text-properties with 'display removed from props"
  (apply oldfun start end (svg-tag--plist-delete props 'display) args))

(defun svg-tag--remove-text-properties-on (args)
  "This installs an advice around remove-text-properties"
  (advice-add 'remove-text-properties
              :around #'svg-tag--remove-text-properties))

(defun svg-tag--remove-text-properties-off (args)
  "This removes the advice around remove-text-properties"
  (advice-remove 'remove-text-properties
                 #'svg-tag--remove-text-properties))

(defun svg-tag-mode-on ()
  "Activate SVG tag mode."
  (add-to-list 'font-lock-extra-managed-props 'display)

  ;; Remove currently active tags
  (when svg-tag--active-tags
    (font-lock-remove-keywords nil
          (mapcar #'svg-tag--build-keywords svg-tag--active-tags)))

  ;; Install tags
  (when svg-tag-tags
    (font-lock-add-keywords nil
          (mapcar #'svg-tag--build-keywords svg-tag-tags)))

  ;; Make a copy of newly installed tags
  (setq svg-tag--active-tags (copy-sequence svg-tag-tags))

  ;; Install advices on remove-text-properties (before & after). This
  ;; is a hack to prevent org mode from removing SVG tags that use the
  ;; 'display property
  (advice-add 'org-fontify-meta-lines-and-blocks
            :before #'svg-tag--remove-text-properties-on)
  (advice-add 'org-fontify-meta-lines-and-blocks
              :after #'svg-tag--remove-text-properties-off)

  ;; Flush buffer when entering read-only
  (add-hook 'read-only-mode-hook
            #'(lambda () (font-lock-flush (point-min) (point-max))))
  
  ;; Redisplay everything to show tags
  (message "SVG tag mode on")
  (cursor-sensor-mode 1)
  (font-lock-flush))

(defun svg-tag-mode-off ()
  "Deactivate SVG tag mode."

  ;; Remove currently active tags
  (when svg-tag--active-tags
    (font-lock-remove-keywords nil
          (mapcar #'svg-tag--build-keywords svg-tag--active-tags)))
  (setq svg-tag--active-tags nil)

  ;; Remove advices on remove-text-properties (before & after)
  (advice-remove 'org-fontify-meta-lines-and-blocks
                 #'svg-tag--remove-text-properties-on)
  (advice-remove 'org-fontify-meta-lines-and-blocks
                 #'svg-tag--remove-text-properties-off)
  (remove-hook 'org-babel-after-execute-hook 'org-redisplay-inline-images)
  
  ;; Redisplay everything to hide tags
  (message "SVG tag mode off")
  (cursor-sensor-mode -1)
  (font-lock-flush))

(define-minor-mode svg-tag-mode
  "Minor mode for graphical tag as rounded box."
  :group 'svg-tag
  (if svg-tag-mode
      (svg-tag-mode-on)
    (svg-tag-mode-off)))

(define-globalized-minor-mode
   global-svg-tag-mode svg-tag-mode svg-tag-mode-on)

(provide 'svg-tag-mode)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; svg-tag-mode.el ends here
