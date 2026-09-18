# Contributing

Read `CLAUDE.md` first: it is the working contract, and the module contract in it is the part
an outside change gets wrong most often.

The short version:

- One module per file, registered with `R:RegisterModule`, with the header comment that lists
  purpose, required API symbols, events and whether the file is hot.
- Every API symbol a module touches appears in its `requires` list. `make api-check` fails
  otherwise, and that check is the main defence against invented functions.
- A module may import `Core` only. Modules never reference each other; cross-module messages go
  through the event broker.
- `OnDisable` fully reverses `OnEnable`. Enable, disable, enable again must leave no timers and
  no subscriptions behind. There is a spec for this per module.
- No user-facing strings outside `Locales/`. No colour literals or texture paths outside the
  theme library.
- `make check` passes before a change is done.
