# tz — treehouse-aware directory jumper

Like [rupa/z](https://github.com/rupa/z) but designed for
[treehouse](https://github.com/kunchenguid/treehouse) worktrees.

Paths are stored **relative to the worktree root**, so your navigation
ranks transfer automatically when you switch between treehouse instances.

> **Note:** This implementation was AI-generated using [Claude](https://claude.ai).

## How it works

- A single datafile (`~/.tz`) stores relative paths with frecency scores
- The current treehouse root is cached in `~/.tz_root`
- `treehouse status` is only called when `$PWD` doesn't match the cached root
- If you're outside a treehouse, you're prompted to jump back or reset

## Install

Add to your `.zshrc` or `.bashrc`:

```bash
. /path/to/tz.sh
```

Then just `cd` around inside treehouse worktrees to build up the database.

## Usage

```
tz           list all entries with ranks
tz .         cd to treehouse root
tz foo       cd to most frecent dir matching foo
tz foo bar   cd to most frecent dir matching foo and bar
tz -r foo    cd to highest ranked dir matching foo
tz -t foo    cd to most recently accessed dir matching foo
tz -l foo    list matches instead of cd
tz -e foo    echo the best match, don't cd
tz -e .      echo the treehouse root
tz -c foo    restrict matches to subdirs of $PWD
tz -x        remove the current directory from the datafile
tz -h        show a brief help message
```

## Key differences from z

| Feature | z | tz |
|---|---|---|
| Paths stored | absolute | relative to treehouse root |
| Datafile | per-machine | shared across worktrees |
| Root awareness | none | auto-detected via `treehouse status` |
| Jump to root | n/a | `tz .` |
| Outside worktree | works anywhere | prompts to return or reset |

## Credits

Based on [z.sh](https://github.com/rupa/z) by rupa deadwyler, licensed
under [WTFPL v2](http://www.wtfpl.net/).

## License

[WTFPL v2](http://www.wtfpl.net/)
