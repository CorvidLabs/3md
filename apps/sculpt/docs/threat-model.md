# Threat model

This matches the one-window app. It is not a claim that the app resists a person who already controls the Mac user account.

## Assets

The appearance choice in `rook.appearance`, and a sculpture file the person chooses to save. There is no note store, clipboard history, or wallet material. The camera and undo stack stay in the session.

## Attackers

- A person who can edit the app's defaults or replace the bundle on this account.
- A remote service. This build does not contact one.

The sandbox protects other users and the rest of the system from this app. It does not protect the app from its own user.

## Entry points

| Entry | What the code does |
| --- | --- |
| Menu bar | Show Sculpt.3md reuses the main window. Settings opens the settings scene. Quit ends the process. Unsaved work asks before quit. |
| Appearance default | Unknown text is treated as system. The value is not a secret and is not sent anywhere. |
| Sculpture file | Open and save use the system file panel. Content detection accepts a sculpture, composition, or sparse world, including native compact voxel `.3mdb` and an explicit portable text or uncompressed-binary copy. A linked composition asks for its project folder for that session. An unsupported schema is refused and is not converted. The bytes are not sent off the Mac. |
| Preview | Core Image draws a Core Text bitmap on Metal when a device exists. No authored shader is loaded. |
| Package | The development packager refuses an unrecognized or symlinked bundle. The product does not spawn a process. |

Ad-hoc local signatures are not notarization.
