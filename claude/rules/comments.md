# Comments

Write only what cannot be recovered from the code or anywhere else.

- Change history, and why it changed → git log / PRs
- Specs → one link to the document; never copy it in
- Design decisions → README / design docs
- Anything a reader gets from the code itself → not needed

Do write what the code cannot show: a quirk in an external spec, a domain constraint, why a seemingly pointless step is needed.
If one line is not enough, it belongs in documentation, not in a comment.

If a comment grows long, question your understanding of the code, not your wording.
