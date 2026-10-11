# Project guidance
## Product and scope

Build a simple Godot web toy with an enclosed 3D box of small primitive shapes.
The app is named **Cargo Hold**, with a single visual style: orange, cobalt,
white and metallic gray shapes in a uniform gray industrial enclosure. A large
real shadow grid also falls across moving pieces, without colored corner lights.

Support tilt and shaking in all three axes, touch grabbing/throwing, portrait,
and landscape. Prioritize iOS Safari while retaining Android Chrome support.
Use minimal controls and a touch/mouse fallback. Do not expand into a PWA or a
larger web interface without a new request.

## Physics and dependencies

- The selected dependency is **Stink-O/box3d-godot**, installed in `addons/box3d/`
  (currently v0.5.0). Its world is separate from Godot's `PhysicsServer3D`.
- Use `Box3DWorld`, `Box3DBody`, and `Box3DCollisionShape`. Use the addon's own
  queries/constraints for interaction. Do not substitute `RigidBody3D`, Jolt,
  Godot Physics, or the removed `godot-box3d` backend for the simulation.
- `project.godot` selecting Jolt does not configure this addon. A native backend
  setting is not evidence that the app uses Box3D.
- Keep the Compatibility renderer. Use GDScript and a small JavaScript bridge;
  do not migrate to C#, a JavaScript physics engine, or a frontend framework.
- Keep GDUnit4 (currently v6.2.0) for meaningful unit and scene integration tests.
- Treat addons as vendor code. Avoid editing/rebuilding them unless a demonstrated
  problem requires it; preserve licenses and the user's existing addon swap.

## Web and hosting constraints

- The installed addon ships only a **threaded release** web library. Export with
  thread and extension support enabled and matching Godot templates.
- HTTPS, `SharedArrayBuffer`, and cross-origin isolation are required. Serve real
  COOP/COEP response headers; a service worker does not fix the initial response.
- Request sensor permissions directly from a user click where required. Correct
  coordinate axes, gravity signs, orientation changes, and stale/null samples.
- Keep web-shell sources under version control and configure the export to use
  them; generated HTML is not the source of truth.
- Use the available **Sites** skill when preparing OpenAI hosting. Verify header,
  asset, and top-level browser requirements early. Do not silently switch hosts
  or physics engines if hosting is incompatible.
- Initial hosting should be owner-private. Sites was selected by the user;
  follow its native publishing approvals without inventing another approval step.
- Discover the current skill location through the session's skills catalog.
  Do not depend on another session's plugin cache path or credentials.

## Verification and handoff

- Separate browser sensor collection from testable motion processing and fixed-step
  physics input. Use injected samples for GDUnit4 tests.
- Check containment under depth-axis gravity and shaking, reset and grab cleanup,
  orientation mapping, lifecycle interruptions, and permission fallback.
- Native checks do not establish mobile web behavior. Record actual tested
  devices/browser versions and report unavailable physical-device checks honestly.
- Keep commands and deployment details in `README.md`; record progress in
  `PLAN.md`. Preserve unrelated changes and do not commit unless requested.
