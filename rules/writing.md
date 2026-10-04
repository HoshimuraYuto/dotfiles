# Writing

Write only what cannot be recovered from anywhere else.

## Structure

Before adding a document, think about who reads it and when.
If no answer comes, the content is not needed.

## Content

Decide what the document is for before writing it.
For a README: what it is, how to install it, how to use it.

If something has a proper home, put it there and link to it.

- Change history, and why it changed → git log / PRs
- Specs → one link to the document; never copy it in

### Comments

- Anything a reader gets from the code itself → not needed

Do write what the code cannot show: a quirk in an external spec, a domain constraint, why a seemingly pointless step is needed.
If you are explaining it outside the code, that explanation is the comment.
If one line is not enough, it belongs in a document, not in a comment.

If a comment grows long, question your understanding of the code, not your wording.
