;; Capture top-level functions, class, and method definitions
(module
  (expression_statement
    (assignment) @assignment
  )
)
(module
  (function_definition) @function
)
(module
  (class_definition
    body: (block
      (expression_statement
        (assignment) @class_assignment
      )
    )
  )
)
(module
  (class_definition
    body: (block
      (function_definition) @method
    )
  )
)
