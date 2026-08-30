import { createGETHandler } from "../../lib/http.js";

export default createGETHandler(async () => ({
  body: { status: "ok" },
  cacheControl: "no-store",
}));
