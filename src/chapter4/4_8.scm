(load "/Users/ruben/Dropbox/EOPL/src/interps/r5rs.scm")
(load "/Users/ruben/Dropbox/EOPL/src/interps/define-datatype.scm")
(load "/Users/ruben/Dropbox/EOPL/src/interps/sllgen.scm")

;The modified/added procedures are marked with ;''

;The rules for car and cdr:
;
;(type-of-expression <<e>> tenv) = (listof t)
;---------------------------------------------
;(type-of-expression <<car (e)>> tenv) = t
;
;
;(type-of-expression <<e>> tenv) = (listof t)
;---------------------------------------------
;(type-of-expression <<cdr (e)>> tenv) = (listof t)

;;;;;;;;;;;;;;;; top level interface ;;;;;;;;;;;;;;;;

(define type-check
  (lambda (string)
    (type-to-external-form
      (type-of-program
        (scan&parse string)))))

(define run
  (lambda (string)
    (eval-program (scan&parse string))))

(define all-groups '(lang4-2))

(define run-all
  (lambda ()
    (run-experiment run use-execution-outcome
      all-groups all-tests)))

(define run-one
  (lambda (test-name)
    (run-test run test-name)))

(define check-all
  (lambda ()
    (run-experiment type-check use-checker-outcome
      all-groups all-tests)))

(define check-one
  (lambda (test-name)
    (run-test type-check test-name)))

(define equal-external-reps? equal?) ; hook for test harness

;;;;;;;;;;;;;;;; grammatical specification ;;;;;;;;;;;;;;;;

(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
      (letter (arbno (or letter digit "_" "-" "?")))
      symbol)
    (number (digit (arbno digit)) number)))

;''
(define the-grammar
  '((program (expression) a-program)
    (expression (number) lit-exp)
    (expression ("true") true-exp)
    (expression ("false") false-exp)
    (expression (identifier) var-exp)
    (expression
      (primitive "(" (separated-list expression ",") ")")
      primapp-exp)
    (expression
      ("if" expression "then" expression "else" expression)
      if-exp)
   (expression
      ("let" (arbno  identifier "=" expression) "in" expression)
      let-exp)
    (expression                         ; typed-parameter is new for 4-2
      ("proc" "(" (separated-list type-exp identifier ",") ")" expression)
      proc-exp)
    (expression
      ("(" expression (arbno expression) ")")
      app-exp)
    (expression
      ("letrec"
        (arbno type-exp identifier
          "(" (separated-list type-exp identifier ",") ")"
          "=" expression) "in" expression)
      letrec-exp)

    (primitive ("+")     add-prim)
    (primitive ("-")     subtract-prim)
    (primitive ("*")     mult-prim)
    (primitive ("add1")  incr-prim)
    (primitive ("sub1")  decr-prim)
    (primitive ("zero?") zero-test-prim)
    (type-exp ("int") int-type-exp)             ; 4-2
    (type-exp ("bool") bool-type-exp)           ; 4-2
    (type-exp                                   ; 4-2
      ("(" (separated-list type-exp "*") "->" type-exp ")")
      proc-type-exp)

    (type-exp
      ("(listof" type-exp ")")
      list-type-exp)
    (expression
      ("list" "(" (separated-list expression ",") ")")
      list-exp)
    (expression
      ("cons" "(" expression "," expression ")")
      cons-exp)
    (expression
      ("null?" "(" expression ")")
      null-exp)
    (expression
      ("emptylist" "[" type-exp "]")
      emptylist-exp)
    (expression
      ("car" "(" expression ")")
      car-exp)
    (expression
      ("cdr" "(" expression ")")
      cdr-exp)
    ))

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatype
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define just-scan
  (sllgen:make-string-scanner the-lexical-spec the-grammar))

;;;;;;;;;;;;;;;; The Type Checker ;;;;;;;;;;;;;;;;

(define type-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (exp) (type-of-expression exp (empty-tenv))))))

;''
(define type-of-expression
  (lambda (exp tenv)
    (cases expression exp
      (lit-exp (number) int-type)
      (true-exp () bool-type)
      (false-exp () bool-type)
      (var-exp (id) (apply-tenv tenv id))
      (if-exp (test-exp true-exp false-exp)
        (let ((test-type (type-of-expression test-exp tenv))
              (false-type (type-of-expression false-exp tenv))
              (true-type (type-of-expression true-exp tenv)))
          (check-equal-type! test-type bool-type test-exp)
       ;^ these tests either succeed or raise an error
          (check-equal-type! true-type false-type exp)
          true-type))
      (proc-exp (texps ids body)
        (type-of-proc-exp texps ids body tenv))
      (primapp-exp (prim rands)
        (type-of-application
          (type-of-primitive prim)
          (types-of-expressions rands tenv)
          prim rands exp))
      (app-exp (rator rands)
        (type-of-application
          (type-of-expression rator tenv)
          (types-of-expressions rands tenv)
          rator rands exp))
      (let-exp (ids rands body)
        (type-of-let-exp ids rands body tenv))
      (letrec-exp (result-texps proc-names texpss idss bodies
                    letrec-body)
        (type-of-letrec-exp
          result-texps proc-names texpss idss bodies
          letrec-body tenv))

      (list-exp (exps)
                (if (> (length exps) 0)
                    (type-of-list-exp exps tenv)
                    (eopl:error 'type-of-expression
                                "A list expression cannot be empty: ~s" exp)))
      (cons-exp (exp1 exp2)
                (type-of-cons-exp exp1 exp2 tenv))
      (null-exp (exp1)
                (cases type (type-of-expression exp1 tenv)
                       (list-type (elem-type)
                                  bool-type)
                       (else (eopl:error 'type-of-expression
                                         "null? can only be applied to list types: ~s" exp1))))
      (emptylist-exp (texp)
                     (list-type (expand-type-expression texp)))
      (car-exp (exp1)
               (cases type (type-of-expression exp1 tenv)
                      (list-type (elem-type)
                                 elem-type)
                      (else (eopl:error 'type-of-expression
                                         "car can only be applied to list types: ~s" exp1))))
      (cdr-exp (exp1)
               (cases type (type-of-expression exp1 tenv)
                      (list-type (elem-type)
                                 (list-type elem-type))
                      (else (eopl:error 'type-of-expression
                                         "cdr can only be applied to list types: ~s" exp1))))
      )))

;''
(define type-of-list-exp
  (lambda (exps tenv)
    (cond ((null? (cdr exps))
           (list-type (type-of-expression (car exps) tenv)))
          (else
            (check-equal-type!
              (type-of-expression (car exps) tenv)
              (type-of-expression (cadr exps) tenv)
              (car exps))
            (type-of-list-exp (cdr exps) tenv)))))

;''
(define type-of-cons-exp
  (lambda (exp1 exp2 tenv)
    (let ((car-type (type-of-expression exp1 tenv)))
      (cases type (type-of-expression exp2 tenv)
             (list-type (elem-type)
                        (check-equal-type! car-type elem-type exp1)
                        (list-type car-type))
             (else (eopl:error 'type-of-cons-exp
                               "The cdr of the cons expression must be a list: ~s" exp2))))))

(define check-equal-type!
  (lambda (t1 t2 exp)
    (if (not (equal? t1 t2))
      (eopl:error 'check-equal-type!
        "Types didn't match: ~s != ~s in~%~s"
        (type-to-external-form t1)
        (type-to-external-form t2)
        exp))))

(define type-of-proc-exp
  (lambda (texps ids body tenv)
    (let ((arg-types (expand-type-expressions texps)))
      (let ((result-type
              (type-of-expression body
                (extend-tenv ids arg-types tenv))))
        (proc-type arg-types result-type)))))

(define type-of-application
  (lambda (rator-type rand-types rator rands exp)
    (cases type rator-type
      (proc-type (arg-types result-type)
        (if (= (length arg-types) (length rand-types))
          (begin
            (for-each
              check-equal-type!
              rand-types arg-types rands)
            result-type)
          (eopl:error 'type-of-expression
            (string-append
              "Wrong number of arguments in expression ~s:"
              "~%expected ~s~%got ~s")
            exp
            (map type-to-external-form arg-types)
            (map type-to-external-form rand-types))))
      (else
        (eopl:error 'type-of-expression
          "Rator not a proc type:~%~s~%had rator type ~s"
          rator (type-to-external-form rator-type))))))

(define types-of-expressions
  (lambda (rands tenv)
    (map (lambda (exp) (type-of-expression exp tenv)) rands)))

(define type-of-let-exp
  (lambda (ids rands body tenv)
    (let ((tenv-for-body
            (extend-tenv
              ids
              (types-of-expressions rands tenv)
              tenv)))
      (type-of-expression body tenv-for-body))))

(define type-of-letrec-exp
  (lambda (result-texps proc-names texpss idss bodies
            letrec-body tenv)
    (let ((arg-typess
            (map
              (lambda (texps)
                (expand-type-expressions texps))
              texpss))
          (result-types
            (expand-type-expressions result-texps)))
      (let ((the-proc-types
              (map proc-type arg-typess result-types)))
        (let ((tenv-for-body ;^ type env for all proc-bodies
                (extend-tenv proc-names the-proc-types tenv)))
          (for-each
            (lambda (ids arg-types body result-type)
              (check-equal-type!
                (type-of-expression
                  body
                  (extend-tenv ids arg-types tenv-for-body))
                result-type
                body))
            idss arg-typess bodies result-types)
          (type-of-expression letrec-body tenv-for-body))))))

;;;;;;;;;;;;;;;; types ;;;;;;;;;;;;;;;;

;''
(define-datatype type type?
  (atomic-type
    (name symbol?))
  (proc-type
    (arg-types (list-of type?))
    (result-type type?))
  (list-type
    (elem-type type?)))

;''
(define expand-type-expression
  (lambda (texp)
    (cases type-exp texp
      (int-type-exp () int-type)
      (bool-type-exp () bool-type)
      (proc-type-exp (arg-texps result-texp)
        (proc-type
          (expand-type-expressions arg-texps)
          (expand-type-expression result-texp)))
      (list-type-exp (texp)
                     (list-type (expand-type-expression texp))))))

(define expand-type-expressions
  (lambda (texps)
    (map expand-type-expression texps)))

;;; types of primitives

(define int-type (atomic-type 'int))
(define bool-type (atomic-type 'bool))

(define type-of-primitive
  (lambda (prim)
    (cases primitive prim
      (add-prim ()
        (proc-type (list int-type int-type) int-type))
      (subtract-prim ()
        (proc-type (list int-type int-type) int-type))
      (mult-prim ()
        (proc-type (list int-type int-type) int-type))
      (incr-prim ()
        (proc-type (list int-type) int-type))
      (decr-prim ()
        (proc-type (list int-type) int-type))
      (zero-test-prim ()
        (proc-type (list int-type) bool-type))
      )))


;;;;;;;;;;;;;;;; type environments ;;;;;;;;;;;;;;;;

(define-datatype type-environment type-environment?
  (empty-tenv-record)
  (extended-tenv-record
    (syms (list-of symbol?))
    (vals (list-of type?))
    (tenv type-environment?)))

(define empty-tenv empty-tenv-record)
(define extend-tenv extended-tenv-record)

(define apply-tenv
  (lambda (tenv sym)
    (cases type-environment tenv
      (empty-tenv-record ()
        (eopl:error 'apply-tenv "Unbound variable ~s" sym))
      (extended-tenv-record (syms vals env)
        (let ((pos (list-find-position sym syms)))
          (if (number? pos)
            (list-ref vals pos)
            (apply-tenv env sym)))))))

;;;;;;;;;;;;;;;; external form of types ;;;;;;;;;;;;;;;;

(define type-to-external-form
  (lambda (ty)
    (cases type ty
      (atomic-type (name) name)
      (proc-type (arg-types result-type)
        (append
          (arg-types-to-external-form arg-types)
          '(->)
          (list (type-to-external-form result-type))))
      (list-type (elem-type)
                 (append
                   '(listof)
                   (list (type-to-external-form elem-type)))))))

(define arg-types-to-external-form
  (lambda (types)
    (if (null? types)
      '()
      (if (null? (cdr types))
        (list (type-to-external-form (car types)))
        (cons
          (type-to-external-form (car types))
          (cons '*
            (arg-types-to-external-form (cdr types))))))))

;;;;;;;;;;;;;;;; the interpreter ;;;;;;;;;;;;;;;;

(define eval-program
  (lambda (pgm)
    (cases program pgm
      (a-program (body)
        (eval-expression body (empty-env))))))

;''
(define eval-expression
  (lambda (exp env)
    (cases expression exp
      (lit-exp (datum) datum)
      (true-exp () 1)
      (false-exp () 0)
      (var-exp (id) (apply-env env id))
      (primapp-exp (prim rands)
        (let ((args (eval-primapp-exp-rands rands env)))
          (apply-primitive prim args)))
      (if-exp (test-exp true-exp false-exp)
        (if (true-value? (eval-expression test-exp env))
          (eval-expression true-exp env)
          (eval-expression false-exp env)))
      (let-exp (ids rands body)
        (let ((args (eval-rands rands env)))
          (eval-expression body (extend-env ids args env))))
      (proc-exp (texps ids body)
        (closure ids body env))
      (app-exp (rator rands)
        (let ((proc (eval-expression  rator env))
              (args (eval-rands rands env)))
          (if (procval? proc)           ; should always be true in
                                        ; typechecked code
            (apply-procval proc args)
            (eopl:error 'eval-expression
              "Attempt to apply non-procedure ~s" proc))))
      (letrec-exp (result-texps proc-names texpss idss bodies
                    letrec-body)
        (eval-expression letrec-body
          (extend-env-recursively proc-names idss bodies env)))

      (list-exp (exps)
                (map (lambda (x) (eval-expression x env)) exps))
      (cons-exp (exp1 exp2)
                (cons (eval-expression exp1 env)
                      (eval-expression exp2 env)))
      (null-exp (exp1)
                (null? (eval-expression exp1 env)))
      (emptylist-exp (texp)
                     '())
      (car-exp (exp1)
               (car (eval-expression exp1 env)))
      (cdr-exp (exp1)
               (cdr (eval-expression exp1 env)))
      )))


(define eval-primapp-exp-rands
  (lambda (rands env)
    (map (lambda (x) (eval-expression x env)) rands)))

(define eval-rands
  (lambda (rands env)
    (map (lambda (x) (eval-rand x env)) rands)))

(define eval-rand
  (lambda (rand env)
    (eval-expression rand env)))

(define apply-primitive
  (lambda (prim args)
    (cases primitive prim
      (add-prim  () (+ (car args) (cadr args)))
      (subtract-prim () (- (car args) (cadr args)))
      (mult-prim  () (* (car args) (cadr args)))
      (incr-prim  () (+ (car args) 1))
      (decr-prim  () (- (car args) 1))
      (zero-test-prim () (if (zero? (car args)) 1 0))
      )))

;;;;;;;;;;;;;;;; booleans ;;;;;;;;;;;;;;;;

(define true-value?
  (lambda (x)
    (not (zero? x))))

;;;;;;;;;;;;;;;; procedures ;;;;;;;;;;;;;;;;

(define-datatype procval procval?
  (closure
    (ids (list-of symbol?))
    (body expression?)
    (env environment?)))

(define apply-procval
  (lambda (proc args)
    (cases procval proc
      (closure (ids body env)
        (eval-expression body (extend-env ids args env))))))

;;;;;;;;;;;;;;;; environments ;;;;;;;;;;;;;;;;

(define-datatype environment environment?
  (empty-env-record)
  (extended-env-record
    (syms (list-of symbol?))
    (vals vector?)
    (env environment?)))

(define apply-env
  (lambda (env sym)
    (cases environment env
      (empty-env-record ()
        (eopl:error 'empty-env "No binding for ~s" sym))
      (extended-env-record (syms vals old-env)
        (let ((pos (rib-find-position sym syms)))
          (if (number? pos)
            (vector-ref vals pos)
            (apply-env old-env sym)))))))

(define empty-env
  (lambda ()
    (empty-env-record)))

(define extend-env
  (lambda (syms vals env)
    (extended-env-record syms (list->vector vals) env)))

(define extend-env-recursively
  (lambda (proc-names idss bodies old-env)
    (let ((len (length proc-names)))
      (let ((vec (make-vector len)))
        (let ((env (extended-env-record proc-names vec old-env)))
          (for-each
            (lambda (pos ids body)
              (vector-set! vec pos (closure ids body env)))
            (iota len) idss bodies)
          env)))))

(define rib-find-position
  (lambda (sym los)
    (list-find-position sym los)))

(define list-find-position
  (lambda (sym los)
    (list-index (lambda (sym1) (eqv? sym1 sym)) los)))

(define list-index
  (lambda (pred ls)
    (cond
      ((null? ls) #f)
      ((pred (car ls)) 0)
      (else (let ((list-index-r (list-index pred (cdr ls))))
              (if (number? list-index-r)
                (+ list-index-r 1)
                #f))))))

(define iota
  (lambda (end)
    (let loop ((next 0))
      (if (>= next end) '()
        (cons next (loop (+ 1 next)))))))

;Tests
;
;> (type-check
;      "list (3, 4)")
;(listof int)
;
;> (type-check
;      "list (3, true)")
;Error reported by check-equal-type!:
;Types didn't match: int != bool in
;(lit-exp 3)
;
;> (type-check
;      "list ()")
;Error reported by type-of-expression:
;A list expression cannot be empty: (list-exp ())
;
;> (type-check
;      "null? (true)")
;Error reported by type-of-expression:
;null? can only be applied to list types: (true-exp)
;
;> (type-check
;      "car (list (true, false, true))")
;bool
;
;> (type-check
;      "cdr (list (true, false, true))")
;(listof bool)
;
;> (type-check
;      "emptylist [bool]")
;(listof bool)
;
;Execution
;
;> (run
;    "let lst = list (113, 12)
;         p = proc ((listof int) addendums) +(car (addendums),
;                                             car (cdr (addendums)))
;     in (p lst)")
;125


;Let's see what happens when we apply car or cdr to an empty list:
;
;> (type-check
;      "car (emptylist [bool])")
;bool
;
;> (type-check
;      "cdr (emptylist [bool])")
;(listof bool)

;It is unreasonable to guarantee that the passed list is non-empty because
;we don't have that information until we evaluate the list expression, which
;happens at run time and not during the type checking phase.
;
;The type parameter in emptylist is necessary because the cons rule needs
;the type of the cdr part so that it can construct a new list of that type,
;with the car par passed as the first argument. If we didn't have the type
;specified in emptylist, then the rule for cons would not apply never.
