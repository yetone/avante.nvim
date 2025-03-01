;; Capture exported functions, arrow functions, variables, classes, and method definitions

(class_declaration) @class
(interface_declaration) @class

(function_definition) @function

(assignment_expression) @assignment

(const_declaration
  (const_element
    (name) @variable))

(_
    body: (declaration_list
      (property_declaration) @class_variable))

(_
  body: (declaration_list
    (method_declaration) @method))
