// Point the viewer at a public GitHub repo, folder, or file.
// The page fetches the tree and the file bytes. The library stays free of network I/O.

export interface GitHubPoint {
  readonly owner: string;
  readonly repo: string;
  /** Named in the URL. Null means the repository's default branch. */
  readonly explicitRef: string | null;
  readonly path: string;
  readonly kind: "repo" | "folder" | "file";
}

export interface RemoteFile {
  readonly path: string;
  readonly data: Uint8Array;
}

export interface LoadedGitHub {
  readonly files: readonly RemoteFile[];
  readonly ref: string;
  readonly label: string;
  readonly truncated: boolean;
}

const TEXT_FILE = /\.(3md|3mdb|md|txt|markdown)$/i;
const MAX_FILES = 400;
const MAX_BYTES = 1_500_000;
const headers = { Accept: "application/vnd.github+json" };

/** Read a public GitHub URL or an owner/repo name. Returns null when it is not one of those. */
export function parseGitHubLocator(input: string): GitHubPoint | null {
  const text = input.trim().replace(/\.git$/i, "").replace(/\/+$/, "");
  if (!text) return null;
  let url: URL | null = null;
  try {
    url = new URL(text);
  } catch {
    url = null;
  }
  if (url && (url.hostname === "github.com" || url.hostname === "www.github.com")) {
    const parts = url.pathname.split("/").filter(Boolean).map(decode);
    if (parts.length < 2) return null;
    const owner = parts[0] ?? "";
    const repo = (parts[1] ?? "").replace(/\.git$/i, "");
    if (!owner || !repo) return null;
    if (parts.length === 2) return { owner, repo, explicitRef: null, path: "", kind: "repo" };
    const mode = parts[2];
    if (mode !== "tree" && mode !== "blob") return null;
    const rest = parts.slice(3);
    return {
      owner,
      repo,
      explicitRef: rest[0] ?? null,
      path: rest.slice(1).join("/"),
      kind: mode === "blob" ? "file" : rest.length > 1 ? "folder" : "repo",
    };
  }
  if (url && url.hostname === "raw.githubusercontent.com") {
    const parts = url.pathname.split("/").filter(Boolean).map(decode);
    if (parts.length < 4) return null;
    return {
      owner: parts[0] ?? "",
      repo: parts[1] ?? "",
      explicitRef: parts[2] ?? null,
      path: parts.slice(3).join("/"),
      kind: "file",
    };
  }
  if (url) return null;
  const parts = text.split("/").filter(Boolean);
  if (parts.length === 2 && parts[0] && parts[1] && !text.includes(" ")) {
    return { owner: parts[0], repo: parts[1].replace(/\.git$/i, ""), explicitRef: null, path: "", kind: "repo" };
  }
  return null;
}

/** Fetch the public files under a GitHub repo, folder, or file. */
export async function loadGitHubPoint(input: string, fetchImpl: typeof fetch = fetch): Promise<LoadedGitHub> {
  const point = parseGitHubLocator(input);
  if (!point) {
    throw new Error("Use a public GitHub repo, folder, or file. Example: github.com/CorvidLabs/3md");
  }
  const repoResponse = await fetchImpl(`https://api.github.com/repos/${point.owner}/${point.repo}`, { headers });
  if (!repoResponse.ok) throw new Error(githubFailure(repoResponse.status, "repository"));
  const repo = await repoResponse.json() as { default_branch?: string };
  const fallbackRef = repo.default_branch || "main";
  const resolved = point.kind === "repo" && !point.explicitRef
    ? { ref: fallbackRef, path: "", kind: "folder" as const }
    : await resolvePath(point, fallbackRef, fetchImpl);
  const loaded = resolved.kind === "file"
    ? { files: [await fetchRaw(point, resolved.ref, resolved.path, fetchImpl)], truncated: false }
    : await fetchTree(point, resolved.ref, resolved.path, fetchImpl);
  const suffix = resolved.path ? `/${resolved.path}` : "";
  return {
    files: loaded.files,
    ref: resolved.ref,
    label: `${point.owner}/${point.repo}${suffix}`,
    truncated: loaded.truncated,
  };
}

async function resolvePath(
  point: GitHubPoint,
  fallbackRef: string,
  fetchImpl: typeof fetch,
): Promise<{ ref: string; path: string; kind: "file" | "folder" }> {
  const segments = [...(point.explicitRef ? [point.explicitRef] : []), ...point.path.split("/").filter(Boolean)];
  const attempts: { ref: string; path: string }[] = [];
  if (!point.explicitRef) attempts.push({ ref: fallbackRef, path: segments.join("/") });
  for (let split = 1; split <= segments.length; split += 1) {
    attempts.push({ ref: segments.slice(0, split).join("/"), path: segments.slice(split).join("/") });
  }
  let lastStatus = 404;
  for (const attempt of attempts) {
    const response = await fetchImpl(contentsUrl(point, attempt.ref, attempt.path), { headers });
    if (!response.ok) {
      lastStatus = response.status;
      continue;
    }
    const body = await response.json() as unknown;
    return { ref: attempt.ref, path: attempt.path, kind: Array.isArray(body) ? "folder" : "file" };
  }
  throw new Error(githubFailure(lastStatus, "path"));
}

async function fetchTree(
  point: GitHubPoint,
  ref: string,
  folder: string,
  fetchImpl: typeof fetch,
): Promise<{ files: RemoteFile[]; truncated: boolean }> {
  const response = await fetchImpl(
    `https://api.github.com/repos/${point.owner}/${point.repo}/git/trees/${encodeURIComponent(ref)}?recursive=1`,
    { headers },
  );
  if (!response.ok) throw new Error(githubFailure(response.status, "tree"));
  const body = await response.json() as { truncated?: boolean; tree?: { path?: string; type?: string; size?: number }[] };
  const prefix = folder ? `${folder}/` : "";
  const paths = (body.tree ?? [])
    .filter((entry) => entry.type === "blob" && entry.path && entry.path.startsWith(prefix))
    .map((entry) => entry.path as string)
    .filter((path) => TEXT_FILE.test(path) && !path.includes("/node_modules/"))
    .filter((path) => {
      const size = body.tree?.find((entry) => entry.path === path)?.size ?? 0;
      return size <= MAX_BYTES;
    })
    .sort((left, right) => left.localeCompare(right));
  const chosen = paths.slice(0, MAX_FILES);
  const files = await mapPool(chosen, 8, (path) => fetchRaw(point, ref, path, fetchImpl));
  return { files, truncated: Boolean(body.truncated) || paths.length > chosen.length };
}

async function fetchRaw(point: GitHubPoint, ref: string, path: string, fetchImpl: typeof fetch): Promise<RemoteFile> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetchImpl(
    `https://raw.githubusercontent.com/${point.owner}/${point.repo}/${encodeURIComponent(ref)}/${encodedPath}`,
  );
  if (!response.ok) throw new Error(githubFailure(response.status, path));
  return { path, data: new Uint8Array(await response.arrayBuffer()) };
}

function contentsUrl(point: GitHubPoint, ref: string, path: string): string {
  const encoded = path.split("/").filter(Boolean).map(encodeURIComponent).join("/");
  const suffix = encoded ? `/${encoded}` : "";
  return `https://api.github.com/repos/${point.owner}/${point.repo}/contents${suffix}?ref=${encodeURIComponent(ref)}`;
}

async function mapPool<Value>(
  items: readonly string[],
  limit: number,
  run: (item: string) => Promise<Value>,
): Promise<Value[]> {
  const results = new Array<Value>(items.length);
  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      const item = items[index];
      if (item === undefined) return;
      results[index] = await run(item);
    }
  }
  const workers = Math.min(limit, items.length);
  await Promise.all(Array.from({ length: workers }, () => worker()));
  return results;
}

function githubFailure(status: number, what: string): string {
  if (status === 403 || status === 429) return "GitHub is rate limiting this browser. Wait a minute and try again.";
  return `That GitHub ${what} is not public, or it does not exist.`;
}

function decode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}
