;; Capture extern functions, variables, public classes, and methods
(function_definition
  (storage_class_specifier) @extern
) @function
(class_specifier
  (public) @class
  (function_definition) @method
) @class
(declaration
  (storage_class_specifier) @extern
) @variable
