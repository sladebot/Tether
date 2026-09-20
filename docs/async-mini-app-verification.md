# Async mini-app verification

Verified September 12, 2026 against the local Hermes API on port 8642.

- A mini-app request is persisted before submission, with its connection ID, model, prompt, and idempotency key.
- Hermes receives `/v1/runs`; the returned run ID is saved. Closing the form or terminating Tether does not cancel the server run.
- On relaunch, Tether polls that run, validates the returned HTML, adds its restrictive content security policy, and saves the app using the job UUID. Repeated recovery cannot create a second app for that job.
- Authentication errors retain the job and ask for a corrected token. Network failures retry with backoff. Failed, cancelled, and interrupted runs finish with a visible status.
- Approval requests are recovered from run status, including their request IDs.

## Live check

An isolated simulator submitted job `E69006F0-1BF3-42BD-861B-117C5C625AEC`, recorded run `run_55f46a6802ee47848748a0c5f351a3d8`, and was terminated. Hermes completed the HTML counter. Relaunching Tether imported the app under the same UUID. A second termination/relaunch left exactly one saved app.

The local bearer handshake returned HTTP 200 using the token loaded into an environment variable from the user's token file. No token was written to the project.

Tailscale remote testing is blocked: the saved hostname does not resolve, and the local Tailscale CLI reports logged out with no Serve configuration. This is separate from local Hermes execution.

## Limits

Before server acceptance, a queued job can only submit while Tether is able to run. Once accepted, Hermes performs the work on the Mac. iOS can suspend Tether; results are reconciled when it opens again. A Hermes process restart may interrupt execution; it is not equivalent to closing the phone app.

## Logo

Generated with the built-in image tool and saved in `Tether/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

Prompt: “Use case: logo-brand. Create a new iOS app icon for Tether, a personal AI chat and mini apps assistant. Minimal bold white custom A monogram formed from two smooth interlocking strokes, with a subtle chat-bubble negative space. Solid black full-bleed square background, flat crisp vector-like edges, centered mark occupying 65% of square. Premium simple silhouette readable at tiny sizes. No words, no gradients, no shadows, no mockup, no rounded outer border. 1024x1024.”
