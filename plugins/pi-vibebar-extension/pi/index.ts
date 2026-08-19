import { createVibeBarExtension } from "./runtime.js";

export default createVibeBarExtension({
  source: "pi-extension",
  tool: "pi",
  executable: "pi",
  settledEvent: "agent_settled",
});
