---
description: Delegate to the refactor subagent (Haiku) for mechanical, well-specified transformations
argument-hint: <exact transformation rule>
---

Use the Agent tool with `subagent_type=refactor` to handle the following transformation:

$ARGUMENTS

The transformation rule must be unambiguous. If `$ARGUMENTS` describes a goal rather than a concrete rule ("clean up the view models", "make this nicer"), do NOT delegate — instead ask the user to specify the exact rule, or suggest routing to `/arch` for a design-level change.
