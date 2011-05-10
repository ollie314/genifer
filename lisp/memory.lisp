;;;; ===========================================================
;;;;                        Memory systems
;;;; ===========================================================

;;;; Genifer/memory.lisp
;;;;
;;;; Copyright (C) 2009 Genint
;;;; All Rights Reserved
;;;;
;;;; Written by YKY
;;;;
;;;; This program is free software; you can redistribute it and/or modify
;;;; it under the terms of the GNU Affero General Public License v3 as
;;;; published by the Free Software Foundation and including the exceptions
;;;; at http://opencog.org/wiki/Licenses
;;;;
;;;; This program is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;; GNU General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU Affero General Public License
;;;; along with this program; if not, write to:
;;;; Free Software Foundation, Inc.,
;;;; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
;;;; ------------------------------------------------------------------------

;;;; ********************************** Introduction ************************************

;;;; Currently the memory is just a simple list of all items, stored in *generic-memory*.

;;; **** Data structure for a Generic-Memory "fact" item
;;; Entries:
;;;     tv           = truth value and confidence
;;;     justifies    = a list of clauses that this fact justifies
;;;     justified-by = a list of clauses that justify this fact
;;; timestamp -- we should not timestamp for every clause, use time-markers instead
(defclass fact-item () (
  (fact         :initarg :fact          :accessor fact)
  (id           :initarg :id            :accessor id)
  (tv           :initarg :tv            :accessor tv            :initform '(1.0 . 1.0))
  (justifies    :initarg :justifies     :accessor justifies     :initform nil)
  (justified-by :initarg :justified-by  :accessor justified-by  :initform nil)
  ))

;;; **** Data structure for a Generic-Memory "rule" item
;;; Entries:
;;;     w            = size of support (ie, total number of times the rule is involved in proofs)
;;;     e+           = positive examples
;;;     e-           = negative examples
;;;     ancestors    = a list of ancestor rules of this rule
;;;     ancestors-to = a list of rules that this rule is ancestor to
(defclass rule-item () (
  (head        :initarg :head        :accessor head)
  (body        :initarg :body        :accessor body)
  (id          :initarg :id          :accessor id)
  (w           :initarg :w           :accessor w            :initform 100)
  (e+          :initarg :e+          :accessor e+           :initform nil)
  (e-          :initarg :e-          :accessor e-           :initform nil)
  (ancestors   :initarg :ancestors   :accessor ancestors    :initform nil)
  (ancestor-to :initarg :ancestor-to :accessor ancestor-to  :initform nil)
))

;;; **** Data structure for a rule / fact
;;; If it is a fact, body = nil
(defclass clause () (
  (id          :initarg :id          :accessor id)
  (confidence  :initarg :confidence  :accessor confidence)
  (head        :initarg :head        :accessor head)
  (body        :initarg :body        :accessor body        :initform nil)
  (tv          :initarg :tv          :accessor tv          :initform nil)
))

;;; Definition of the truth-value "T"
(defparameter *true* '(1.0 . 1.0))

(defvar *generic-memory*)
(defvar *memory-size*)
(defvar *newly-added*)
(defvar new-rule)

;;; **** Initialize memories
(defun init-memories ()
  ;; Generic Memory
  (setf *generic-memory* nil)
  ;; index
  (setf *memory-size* 0)
  ;; counter used in batch processing
  (setf *newly-added* 0)

  (format t ";; Adding knowledge to KB.... ~%")

  (cond
    ((equalp *logic-type* "P")
      (load "examples-P.lisp"))
    ((equalp *logic-type* "Z")
      (load "examples-Z.lisp"))
    (T
      (load "examples-P(Z).lisp")))

  (format t ";; Working Memory initialized... ~%"))

(defun system-test ()
  (setf *abduce* nil)
  ; (setf *debug-level* 10)
  (format t "# ~1,5@T t elapsed: ~1,18@T expected TV ~1,32@T confidence ~1,48@T substitutions~%")
  (format t "---------------------------------------------------------------------~%")
  ; format:  query expected-tv expected-sub
  (test-1-query 1 "Is Kellie having fun?"
    '(having-fun kellie) '(0.3 . 0.9) nil)         ; example 1
  (test-1-query 2 "Is Kellie at the bar?"
    '(at-bar kellie) '(0.3 . 0.9) nil)             ; example 1 **** not yet ready
  (test-1-query 3 "Can robot reach the goal?"
    '(goal robot) '(0.9 . 0.9) nil)                ; example 2
  (test-1-query 4 "Can robot2 reach the goal?"
    '(goal robot2) 'fail nil)                      ; example 2
  (test-1-query 5 "Is C  a chair?"
    '(chair c) '(0.7 . 0.9) nil)                   ; example 3
  (test-1-query 6 "Is C2 a chair?"
    '(chair c2) 'fail nil)                         ; example 3
  (test-1-query 7 "Is C  a chair? (longer version)"
    '(chair2 c) '(0.7 . 0.9) nil)                  ; example 3b
  (test-1-query 8 "Is C2 a chair? (longer version)"
    '(chair2 c2) 'fail nil)                        ; 3b
  (test-1-query 9 "Is John happy?"
    '(happy john) '(1.0 . 0.9) nil)                ; example 4
  ; example 5
  (test-1-query 10 "Who is John's grandson?"
    '(grandparent john ?99) '(1.0 . 0.9) '(?99 . (son-of (son-of john))))
  (test-1-query 11 "Who is John's grandson? (with possible variable crash)"
    '(grandparent john ?1) '(1.0 . 0.9) '(?99 . (son-of (son-of john))))
  (test-1-query 12 "Who has a grandparent?"
    '(grandparent ?1 ?2) '(1.0 . 0.9) '())
  (test-1-query 13 "Does John has a grandparent?"
    '(grandparent ?1 john) 'fail nil)
  ; example 6
  (test-1-query 14 "Is John Paul's grandpa?"
    '(grandpa john paul) '(1.0 . 0.9) '(?a . pete))
  (test-1-query 15 "Is John  Sam's grandpa?"
    '(grandpa john sam) '(1.0 . 0.9) '(?b . mary))
  (test-1-query 16 "To whom is Sam a grandpa?"
    '(grandpa ?1 sam) '(1.0 . 0.9) '((?1 . john) (?a . mary)))
)

(defun test-1-query (test-number text query &optional expected-tv expected-sub)
  (setf timer (get-internal-run-time))
  (backward-chain query)
  (setf solutions (solutions proof-tree))
  (if (equal 'fail solutions)
    (setf s1 nil)
    (setf s1 (car solutions)))
  (if (null s1)
    (if (equal 'fail expected-tv)
      (setf tv-accuracy         100.0
            confidence-accuracy 100.0)
      (setf tv-accuracy         0.0
            confidence-accuracy 0.0))
    (if (equal 'fail expected-tv)
      (setf tv-accuracy         0.0
            confidence-accuracy 0.0)
      (progn
        ;(setf tv-accuracy         (* 100.0 (- 1.0 (abs (- (car (tv s1)) (car expected-tv))))))
        ;(setf confidence-accuracy (* 100.0 (- 1.0 (abs (- (cdr (tv s1)) (cdr expected-tv))))))
        (setf tv-accuracy         (* 100.0 (- 1.0 (abs (- (message s1) (car expected-tv))))))
        (setf confidence-accuracy (* 100.0 (- 1.0 (abs (-    0.0       (cdr expected-tv))))))
      )))
  ; (format t "~a ~%" text)
  (format t "~a ~1,5@T ~aus ~1,18@T ~a% ~1,32@T ~a% ~%" test-number
                     (- (get-internal-run-time) timer)
                     tv-accuracy confidence-accuracy))

;;; **** Add a clause to memory
;;; TODO:  label, and the stack from abduction
(defun add-to-memory (clause label)
  ;; check if the clause is already in memory -- this may be time-consuming.
  (dolist (item *generic-memory*)
    (if (equal clause (slot-value item 'clause))
      (return-from add-to-memory)))     ; if so, exit
  ;; if not in memory, add it
  (if (is-ground clause)
    (add-fact-to-mem clause)
    (add-rule-to-mem clause)))

(defvar new-fact)

;;; **** Add a fact to Generic Memory
(defun add-fact-to-mem (fact &optional tv justifies justified-by)
  (if (null tv)
    (setf tv (cons 1.0 1.0)))          ; default TV
  (****DEBUG 1 "adding fact to memory: ~a" fact)
  ;; create an object
  (setf new-fact (make-instance 'fact-item
                          :fact         fact
                          :id           *memory-size*
                          :tv           tv
                          :justifies    justifies
                          :justified-by justified-by))
  ;; increase the index
  (incf *memory-size*)
  (incf *newly-added*)
  ;; add the object to GM, by appending to the end of list
  (setf *generic-memory* (cons new-fact *generic-memory*)))

;;; **** Add a rule to Generic Memory
(defun add-rule-to-mem (head &optional body w e+ e- ancestors ancestor-to)
  ;; Set default values:
  (****DEBUG 1 "adding rule to memory: ~a <- ~a" head body)
  (if (null body) (setf body '(*bodyless*)))
  (if (null w )   (setf w    100))
  (if (null e+)   (setf e+   0))
  (if (null e-)   (setf e-   0))
  ;; create an object
  (setf new-rule (make-instance 'rule-item
                          :head         head
                          :body         body
                          :id           *memory-size*
                          :w            w
                          :e+           e+
                          :e-           e-
                          :ancestors    ancestors
                          :ancestor-to  ancestor-to))
  ;; increase the index
  (incf *memory-size*)
  (incf *newly-added*)
  ;; add the object to GM, by appending to the end of list
  (setf *generic-memory* (cons new-rule *generic-memory*)))

(defun delete-memory-item (item)
  (setf ptr *generic-memory*)
  ;; Special case:
  (if (eql item ptr)
    (return-from delete-memory-item
      (setf *generic-memory* (cdr *generic-memory*))))
  ;; Otherwise, find the item
  (loop
    (if (eql item (cdr ptr)) (return))
    (setf ptr (cdr ptr)))
  ;; Delete it
  (setf (cdr ptr) (cdr item)))

;;; Fetch all clauses in KB with the given head-predicate
;;; Return: a list of rules
(defun fetch-clauses (head-predicate)
  (let ((facts-list (list nil))
        (rules-list (list nil)))
    (dolist (item *generic-memory*)
      ;; is it a rule?
      (if (eql (type-of item) 'rule-item)
        (let ((head (head item))
              (body (body item)))
          ;; Does head of rule match head-predicate?
          (if (equal (car head) head-predicate)
            (progn
              ;; calculate the confidence c from w
              ;; the function is defined in "PZ-calculus.lisp"
              (setf confidence (convert-w-2-c (w item)))
              ;; add it to list-to-be-returned
              (nconc rules-list (list (make-instance 'clause
                                        :id         (id item)
                                        :confidence confidence
                                        :head       head
                                        :body       body))))))
        ;; If it is a fact:
        ;; Does fact match head-predicate?
        (if (equal (car (fact item)) head-predicate)
          (let ((tv (tv item)))
            ;; add it to list-to-be-returned
            (nconc facts-list (list (make-instance 'clause
                                      :id         (id item)
                                      :confidence (cdr tv)
                                      :head       (fact item)
                                      :tv         tv)))))))
    ;; return the 2 lists, discarding the leading 'nil' items
    (values (cdr facts-list) (cdr rules-list))))

;;; Comparison predicate for "sort" in function "fetch-clauses"
;;; should return true iff x1 is strictly less than x2
;;; if x1 is greater than or equal to x2, return false
;;; sort seems to order from small to big -- we need to reverse this -- biggest confidence 1st
;;; each element is a list:  (confidence head body)
(defun compare-items (x1 x2)
  (> (car x1) (car x2)))

;;; This function is used in natural-language.lisp
(defvar *entity-counter* 1)
;;; **** Creates a new entity
(defun new-entity ()
  (incf *entity-counter*))

;;; ------------------------ miscellaneous functions -------------------------

;;; **** Print out memory contents
(defun dump-memory ()
  (dolist (item *generic-memory*)
    (if (eql (type-of item) 'fact-item)
      ;; print a fact item
      (progn
        (format t "**** [~a] fact: ~a ~%" (id item) (fact item))
        (setf tv (tv item))
        (format t "  TV:           ~a ~%" (car tv))
        (format t "  confidence:   ~a ~%" (cdr tv))
        (format t "  justifies:    ~a ~%" (justifies    item))
        (format t "  justified-by: ~a ~%" (justified-by item)))
      ;; print a rule item
      (progn
        (format t "**** [~a] rule: ~%"    (id          item))
        (format t "  head:         ~a ~%" (head        item))
        (format t "  body:         ~a ~%" (body        item))
        (format t "  w:            ~a ~%" (w           item))
        (format t "  e+:           ~a ~%" (e+          item))
        (format t "  e-:           ~a ~%" (e-          item))
        (format t "  ancestors:    ~a ~%" (ancestors   item))
        (format t "  ancestors-to: ~a ~%" (ancestor-to item))))))
