# Steam Workshop staging

This directory contains a sanitized template for staging Alien Crisis: Grey
Consensus to the Hearts of Iron IV Steam Workshop (`appid 394360`). Active
Workshop metadata is local deployment state and must not be committed.

The sanitized example describes the public development and playtesting release
for version `0.6.0` and defaults to public visibility.

## Prepare a local staging file

1. Copy `workshop_item_394360.example.vdf` to a new `.vdf` file in this
   directory.
2. Replace the placeholder content and preview paths with absolute paths on the
   publishing machine.
3. Leave `publishedfileid` as `0` only when creating a new item. For an update,
   use the existing item's numeric ID.
4. Confirm the intended visibility before every upload. Steam uses `0` for
   Public and `2` for Private; the example defaults to Public.
5. Keep the local `.vdf`, SteamCMD logs, account data, and Steam Guard material
   outside version control.

The content folder is the repository's `Mod` directory. The preview file is
`Mod/thumbnail.png` and is already sized for the launcher and Workshop.
Keep the canonical public source URL in the Workshop description:
`https://github.com/corbett3289/HOI4AL-1`.

## Upload

Use Valve's official SteamCMD interactively. Never place a password, guard code,
or reusable login command in this repository.

```powershell
& '<path-to-steamcmd>/steamcmd.exe' `
  +login '<steam-account-name>' `
  +workshop_build_item '<absolute-path-to-local-vdf>' `
  +quit
```

On success, SteamCMD writes the permanent item ID into the local staging VDF.
Preserve that local ID for future updates, but do not copy deployment identifiers
or manifest numbers into public source documentation.

Workshop publication grants platform rights under the Steam Subscriber
Agreement and remains subject to the Paradox User Agreement. Review both before
publishing an item or changing its visibility.
