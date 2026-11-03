# Where openhuman differs from OpenAI on purpose

Behaviour that knowingly departs from OpenAI's API semantics, and why.
Anything not listed here aims to match OpenAI.

- **Vector-store search sees a bounded set of files.** Filters on file
  `attributes` are applied by the server before the seat sees anything;
  past `OPENHUMAN_VECTOR_SEARCH_MAX_BYTES` only the most relevant (then
  newest) matching files are attached (see `server-env.md`).
