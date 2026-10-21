# leonard_acp

ACP (Agent Client Protocol) model provider for Leonard. It drives any
ACP-compatible coding agent as a per-turn decision oracle behind
`leonard_agent`'s `ModelProvider` seam, so `leonard_cli` can steer a live app
with an external agent instead of a hosted model.

Part of the [lenny](https://github.com/memento-engineering/lenny) workspace.

## Drive the DevTools panel with GitHub Copilot or Codex

The Leonard DevTools panel can use a coding agent you are already signed in
to as its brain. The panel runs in a browser and cannot start processes, so a
small bridge on your machine starts the agent and serves it to the panel over
the Dart Tooling Daemon (DTD).

1. Install and sign in to the agent:
   - **GitHub Copilot CLI**: install `copilot`, run it once and sign in.
   - **Codex**: needs `npx`; the bridge runs
     `@agentclientprotocol/codex-acp`, signed in with your Codex account.
2. Add the bridge to your app's dev dependencies, next to `leonard_flutter`:

   ```yaml
   dev_dependencies:
     leonard_acp: ^0.2.2
   ```

3. Run your app and note the DTD address it prints:

   ```sh
   flutter run --print-dtd
   # The Dart Tooling Daemon is available at: ws://127.0.0.1:PORT/SECRET=
   ```

4. In a second terminal, from the app's directory, start the bridge with
   that address:

   ```sh
   dart run leonard_acp:dtd_host --dtd-uri 'ws://127.0.0.1:PORT/SECRET=' --dtd-secret x
   ```

   `--dtd-secret` must be non-empty; any value works. Add `-v` to see the
   agent's own log.

5. Open DevTools from `flutter run`, go to the **leonard** tab, then
   **Settings**. Choose provider **acp**, then the harness (`copilot` or
   `codex-acp`) and a model from the list the agent reports. Start a run with
   a goal.

If the panel shows `acp — no ACP host is registered`, the bridge is not
running against this app's DTD, or it started after the panel opened: the
panel looks for the bridge when it loads, so reload the panel. The panel and
the bridge must agree on the service name: use `leonard_acp` 0.2.2 or later
with `leonard_flutter` 0.4.2 or later. The bridge serves one session at a time;
starting a new run replaces the previous one.

What the agent does in this mode: it chooses Leonard's next action each
turn from a text description of the screen. It does not get screenshots.
Leonard grants it no file system and no terminal and refuses every
permission request it makes. An agent's own built-in tools that need no
permission (for example read-only file tools) are governed by the agent, in
the directory the bridge was started from (`--cwd`).
