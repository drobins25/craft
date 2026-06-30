; Vendored from:
; https://raw.githubusercontent.com/tree-sitter/tree-sitter-java/master/queries/tags.scm
; Pruned to the patterns this grammar version supports (7 kept, 0 dropped).
; Regenerate with: node tags/vendor-queries.mjs

(class_declaration
  name: (identifier) @name) @definition.class

(method_declaration
  name: (identifier) @name) @definition.method

(method_invocation
  name: (identifier) @name
  arguments: (argument_list) @reference.call)

(interface_declaration
  name: (identifier) @name) @definition.interface

(type_list
  (type_identifier) @name) @reference.implementation

(object_creation_expression
  type: (type_identifier) @name) @reference.class

(superclass (type_identifier) @name) @reference.class
