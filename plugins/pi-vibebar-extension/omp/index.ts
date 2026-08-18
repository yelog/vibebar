import { createVibeBarExtension } from "../runtime.js";

export default createVibeBarExtension({
  source: "oh-my-pi-extension",
  tool: "oh-my-pi",
  executable: "omp",
  settledEvent: "session_stop",
});
