#lang eopl

(#%provide interp)
(define (interp src) (value-of-program-dbg-store (scan&parse src)))

; Program ::= Expression
;
; Expression ::= Number
;            ::= primitive-procedure({Expression}*(,))
;            ::= proc ({Identifier}*(,)) Expression
;            ::= (Expression {Expression}*)
;            ::= if Expression then Expression else Expression
;            ::= Identifier
;            ::= let {Identifier = Expression}*(,) in Expression
;            ::= letrec {Identifier ({Identifier}*(,)) = Expression}*(,) in Expression
;            ::= set Identifier = Expression
;            ::= begin {Expression}*(,) end
;
; ExpVal = Number + Boolean + Proc
; DenVal = Ref(ExpVal + Thunk)
;
; primitive-procedures: minus, diff(-), addition(+), ,multiplication(*),
;                       quotient, remainder,
;                       zero?, equal?, greater?, less?,
;
; environment: symbol -> DenVal
; store: Ref -> ExpVal

(define scanner-spec
  '((white-sp (whitespace) skip)
    (commont ("#" (arbno (not #\newline))) skip)
    (number (digit (arbno digit)) number)
    (identifier
      ((or letter)
       (arbno
         (or "-" "_" letter digit))) symbol)))

(define grammar-spec
  '((program (expression) a-program)
    (expression (number) number-exp)
    (expression (identifier) var-exp)
    (expression
      (primitive
        "(" (separated-list expression ",") ")")
      apply-primitive-exp)
    (expression
      ("proc" "(" (separated-list identifier ",") ")"
       expression)
      proc-exp)
    (expression
      ("(" expression (arbno expression) ")")
      call-exp)
    (expression
      ("if" expression "then" expression "else" expression)
      if-exp)
    (expression
      ("let" (separated-list identifier "=" expression ",") "in" expression)
      let-exp)
    (expression
      ("letrec"
       (separated-list
         identifier
         "(" (separated-list identifier ",") ")" "=" expression
         ",")
       "in" expression)
      letrec-exp)
    (expression
      ("set" identifier "=" expression)
      assign-exp)
    (expression
      ("begin" (separated-list expression ",") "end")
      begin-exp)
    (primitive ("+") add-prim)
    (primitive ("-") diff-prim)
    (primitive ("*") mult-prim)
    (primitive ("minus") minus-prim)
    (primitive ("quotient") quotient-prim)
    (primitive ("remainder") remainder-prim)
    (primitive ("zero?") zero?-prim)
    (primitive ("equal?") equal?-prim)
    (primitive ("greater?") greater?-prim)
    (primitive ("less?") less?-prim)))

(sllgen:make-define-datatypes
  scanner-spec grammar-spec)

(define scan&parse
  (sllgen:make-string-parser
    scanner-spec grammar-spec))

(eopl:pretty-print
  (sllgen:list-define-datatypes
    scanner-spec grammar-spec))
;
;(define test-parse
;  (sllgen:make-rep-loop
;    "> " (lambda (x) x)
;    (sllgen:make-stream-parser
;      scanner-spec grammar-spec)))
;
;(test-parse)

; refval ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype refval refval?
  (a-ref (ref integer?)))

(define (refval->ref val)
  (cases refval val
    (a-ref (ref) ref)))

; expval ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype expval expval?
  (num-val
    (num number?))
  (bool-val
    (bool boolean?))
  (proc-val
    (proc proc?)))

(define (report-expval-extractor-error type val)
  (eopl:error "Type error:" val type))

(define (expval->num val)
  (cases expval val
    (num-val (num) num)
    (else (report-expval-extractor-error 'num val))))

(define (expval->bool val)
  (cases expval val
    (bool-val (bool) bool)
    (else (report-expval-extractor-error 'bool val))))

(define (expval->proc val)
  (cases expval val
    (proc-val (proc) proc)
    (else (report-expval-extractor-error 'proc val))))

(define (minus val)
  (cases expval val
    (num-val (num) (num-val (- num)))
    (else report-expval-extractor-error 'num val)))

; procedure ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype proc0 proc?
  (procedure
    (list-of-var (list-of symbol?))
    (body expression?)
    (env environment?)))

(define (proc-val-procedure args body env)
  (proc-val (procedure args body env)))

(define (apply-proc proc list-of-val)
  (cases proc0 proc
    (procedure (list-of-var body env)
      (let ((nvars (length list-of-var))
            (nvals (length list-of-val)))
        (if (= nvars nvals)
          (value-of
            body
            (extend-env env list-of-var list-of-val))
          (report-arguments-not-match
            list-of-var list-of-val))))))

(define (report-arguments-not-match vars vals)
  (eopl:error "args not match" vars vals))

; thunk ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype thunk thunk?
  (a-thunk
    (exp expression?)
    (env environment?)))

(define (value-of-thunk th)
  (cases thunk th
    (a-thunk (exp env)
      (value-of exp env))))

; store ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define the-store 'uninitialized)

(define (empty-store) '())

(define (get-store) the-store)

(define (initialize-store!)
  (set! the-store (empty-store)))

(define (reference? v) (integer? v))

(define (newref val)
  (let ((next-ref (length the-store)))
    (set! the-store (append the-store (list val)))
    next-ref))

(define (deref ref)
  (list-ref the-store ref))

(define (setref! ref val)
  (define (iter st ref)
    (if (null? st)
      (report-invalid-reference ref the-store)
      (if (zero? ref)
        (cons val (cdr st))
        (cons (car st) (iter (cdr st) (- ref 1))))))
  (set! the-store
    (iter the-store ref)))

(define (report-invalid-reference ref the-store)
  (eopl:error "invalid reference:" ref the-store))

; environment ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype frame frame?
  (frame-vec (vec vector?)))

(define (a-frame vars vals)
  (frame-vec (vector vars vals)))

(define (empty-frame)
  (a-frame '() '()))

(define (frame-set! frm vars vals)
  (cases frame frm
    (frame-vec (vec)
      (vector-set! vec 0 vars)
      (vector-set! vec 1 vals))))

(define (frame-vars frm)
  (cases frame frm
    (frame-vec (vec) (vector-ref vec 0))))

(define (frame-vals frm)
  (cases frame frm
    (frame-vec (vec) (vector-ref vec 1))))

(define-datatype environment environment?
  (empty-env)
  (extend-env-frame
    (enclosing-environemt environment?)
    (frm frame?)))

(define (extend-env env vars vals)
  ; assert (= (length list-of-symbol) (length list-of-exp))
  (define (ref-or-newref val)
    (if (refval? val)
      (refval->ref val)
      (newref val)))
  (extend-env-frame env (a-frame vars (map ref-or-newref vals))))

(define (extend-env-rec env list-of-name list-of-args list-of-body)
  ; assert (= (length list-of-name) (length list-of-args) (length list-of-body))
  (let* ((frm (empty-frame))
         (new-env (extend-env-frame env frm))
         (mk-proc-ref (lambda (args body)
                        (newref (proc-val-procedure args body new-env)))))
    (frame-set! frm
                list-of-name
                (map mk-proc-ref list-of-args list-of-body))
    new-env))

(define (apply-env env search-var)
  (define (search-env env)
    (cases environment env
      (empty-env () (report-unbound-var search-var))
      (extend-env-frame (enclosing-env frm)
        (search-frame (frame-vars frm) (frame-vals frm) enclosing-env))))
  (define (search-frame vars vals next-env)
    (if (null? vars)
      (search-env next-env)
      (if (eqv? search-var (car vars))
        (car vals)
        (search-frame (cdr vars) (cdr vals) next-env))))
  (search-env env))

(define (report-unbound-var search-var)
  (eopl:error "Unbound variable" search-var))

; value-of ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define (value-of-program pgm)
  (initialize-store!)
  (cases program pgm
    (a-program (exp1)
      (value-of exp1 (init-env)))))

(define (print-store)
  (define (iter count lst)
    (if (null? lst)
      'done
      (begin
        (display count)(display " ")
        (eopl:pretty-print (car lst))
        (iter (+ count 1) (cdr lst)))))
  (display "###")(newline)
  (iter 0 the-store)
  (display "###")(newline))

(define (value-of-program-dbg-store pgm)
  (initialize-store!)
  (let ((ret (cases program pgm
               (a-program (exp1)
                 (value-of exp1 (init-env))))))
    (print-store)
    ret))

(define (value-of-operand exp env)
  (cases expression exp
    (number-exp (number) (value-of exp env))
    (var-exp (var) (a-ref (apply-env env var)))
    (proc-exp (list-of-var body) (value-of exp env))
    (else (a-thunk exp env))))

(define (value-of exp env)
  (define (value-of-list-of-exp list-of-exp)
    (map (lambda (e) (value-of e env)) list-of-exp))
  (define (value-of-list-of-operand list-of-exp)
    (map (lambda (e) (value-of-operand e env)) list-of-exp))
  (define (get-last list-of-expval)
    ; assert (not (null? list-of-expval))
    (if (null? (cdr list-of-expval))
      (car list-of-expval)
      (get-last (cdr list-of-expval))))
  (cases expression exp
    (number-exp (number) (num-val number))
    (var-exp (var)
      (let* ((ref (apply-env env var))
             (w (deref ref)))
        (if (expval? w)
          w
          (let ((val (value-of-thunk w)))
            (setref! ref val)
            val))))
    (apply-primitive-exp (prim list-of-exp)
      (apply-primitive
        prim
        (value-of-list-of-exp list-of-exp)))
    (proc-exp (list-of-var body)
      (proc-val-procedure list-of-var body env))
    (call-exp (rator rands)
      (apply-proc
        (expval->proc (value-of rator env))
        (value-of-list-of-operand rands)))
    (if-exp (exp1 exp2 exp3)
      (if (expval->bool (value-of exp1 env))
        (value-of exp2 env)
        (value-of exp3 env)))
    (let-exp (list-of-symbol list-of-exp body)
      (let ((new-env (extend-env
                       env
                       list-of-symbol
                       (value-of-list-of-operand list-of-exp))))
        (value-of body new-env)))
    (letrec-exp (list-of-name list-of-args list-of-body letrec-body)
      (let ((new-env (extend-env-rec
                       env
                       list-of-name
                       list-of-args
                       list-of-body)))
        (value-of letrec-body new-env)))
    (assign-exp (var exp)
      (let ((expv (value-of exp env)))
        (setref! (apply-env env var) expv)
        42))
    (begin-exp (list-of-exp)
      (if (null? list-of-exp)
        (report-no-exps-in-begin)
        (get-last (value-of-list-of-exp list-of-exp))))))

(define (report-no-exps-in-begin)
  (eopl:error "no expressions between begin and end"))

(define (init-env) (empty-env))

(define (apply-primitive prim list-of-expval)
  (cases primitive prim
    (add-prim ()
      (num-val (apply + (map expval->num list-of-expval))))
    (diff-prim ()
      (num-val (apply - (map expval->num list-of-expval))))
    (mult-prim ()
      (num-val (apply * (map expval->num list-of-expval))))
    (minus-prim () (apply minus list-of-expval))
    (quotient-prim ()
      (num-val (apply quotient (map expval->num list-of-expval))))
    (remainder-prim ()
      (num-val (apply remainder (map expval->num list-of-expval))))
    (zero?-prim ()
      (bool-val (apply zero? (map expval->num list-of-expval))))
    (equal?-prim ()
      (bool-val (apply = (map expval->num list-of-expval))))
    (greater?-prim ()
      (bool-val (apply > (map expval->num list-of-expval))))
    (less?-prim ()
      (bool-val (apply < (map expval->num list-of-expval))))))

; read-eval-print ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define read-eval-print
  (sllgen:make-rep-loop
    "> " value-of-program
    (sllgen:make-stream-parser
      scanner-spec grammar-spec)))

;(read-eval-print)
