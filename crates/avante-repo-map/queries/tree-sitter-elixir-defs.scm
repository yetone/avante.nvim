; * modules and protocols
(call
  target: (identifier) @ignore
  (arguments (alias) @class)
  (#match? @ignore "^(defmodule|defprotocol)$"))

; * functions
(call
  target: (identifier) @ignore
  (arguments
    [
      ; zero-arity functions with no parentheses
      (identifier) @method
      ; regular function clause
      (call target: (identifier) @method)
      ; function clause with a guard clause
      (binary_operator
        left: (call target: (identifier) @method)
        operator: "when")
    ])
  (#match? @ignore "^(def|defdelegate|defguard|defn)$"))
