# The Project

This is a Nextflow pipeline written to create the CRUK-CI Bioinformatics standard reference
genomes structure.

# Code style

Use the Allman brace style except when you have very small closures.

Under the strict/v2 syntax parser, a trailing closure argument's opening brace must be on
the same line as the method call it belongs to (e.g. `list.each { x -> ... }`). Putting the
brace on its own line, Allman-style, does not fail to parse; it silently splits into two
statements: a bare property read (e.g. `list.each`) followed by an orphaned closure literal
that is evaluated and discarded. This produces a confusing runtime error rather than a parse
error. When Allman style is wanted for a trailing closure, add a trailing backslash
line-continuation after the method call so no newline token is emitted before the brace:

```groovy
bclconvertFiles.each \
{
    bclconvertFile ->
    ...
}
```

# Source Control

You can issue Git or Subversion commands to read files but do not issue commands that change
the state of the project. Specifically, do not issue "commit" or "push" commands.

# Nextflow References

1. Migration to version 26: https://docs.seqera.io/nextflow/migrations/26-04
2. Record types: https://docs.seqera.io/nextflow/migrations/26-04#record-types
3. Strict syntax: https://docs.seqera.io/nextflow/strict-syntax
4. Typed processes: https://docs.seqera.io/nextflow/process-typed
5. Typed workflows: https://docs.seqera.io/nextflow/workflow-typed
6. Typed operators: https://docs.seqera.io/nextflow/reference/operator-typed

# Out of Bounds

Do not try to read the entire home directory. Limit yourself to directories mentioned in
the prompts.

# Hints

Where there is a function or similar complicated Groovy code in Nextflow *.nf files,
consider moving this code into a Groovy file under "lib" rather than rewriting it as
compliant with the Nextflow strict parser.

# Warnings

You might need to flag uses of the "first()" method on data channels (not Groovy collections)
as they can cause the pipeline to hang when the channel has nothing going through it.
