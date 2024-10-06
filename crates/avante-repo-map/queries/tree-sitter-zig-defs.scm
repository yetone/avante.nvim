 ;; Capture functions, structs, methods, variable definitions, and unions in Zig
(variable_declaration (identifier)
  (struct_declaration
        (container_field) @class_variable))

(variable_declaration (identifier)
  (struct_declaration
        (function_declaration
            name: (identifier) @method)))

(variable_declaration (identifier)
  (enum_declaration
    (container_field
      type: (identifier) @enum_item)))

(variable_declaration (identifier)
  (union_declaration
    (container_field
      name: (identifier) @union_item)))

(source_file (function_declaration) @function)

(source_file (variable_declaration (identifier) @variable))
