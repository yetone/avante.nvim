;; Capture top-level methods, class definitions, and methods within classes

(class
  (body_statement
    (call)? @class_call
    (assignment)? @class_assignment
    (method)? @method
  )
) @class

(program
  (method) @function
)
(program
  (assignment) @assignment
)

(module) @module

(module
  (body_statement
    (call)? @class_call
    (assignment)? @class_assignment
    (method)? @method
  )
)
