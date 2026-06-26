// Type declarations for @corvidlabs/three-md-element.
//
// Hand-authored and self-contained (no external imports) so the published
// package's types resolve without depending on the parser package. The shapes
// mirror @corvidlabs/threemd's Document and Plane.

export type Mode =
  | "stack"
  | "play"
  | "single"
  | "present"
  | "blend"
  | "map"
  | "layers"
  | "elevator";

export interface ThreeMDPlane {
  readonly z: number;
  readonly label: string | null;
  readonly x: number | null;
  readonly y: number | null;
  readonly attributes: Readonly<Record<string, string>>;
  readonly body: string;
}

export interface ThreeMDDocument {
  readonly version: string;
  readonly axis: string;
  readonly title: string | null;
  readonly metadata: Readonly<Record<string, string>>;
  readonly preamble: string | null;
  readonly planes: readonly ThreeMDPlane[];
}

/** Detail of the `planechange` event dispatched when the focused plane changes. */
export interface PlaneChangeDetail {
  readonly index: number;
  readonly z: number;
  readonly label: string | null;
  readonly plane: ThreeMDPlane;
}

/**
 * The `<three-md>` custom element: an interactive renderer for the 3md format.
 * Importing the package registers the element via `customElements.define`.
 */
export declare class ThreeMDElement extends HTMLElement {
  static get observedAttributes(): string[];
  /** The parsed document, or null before content has loaded. */
  get document(): ThreeMDDocument | null;
  /** The parse error from the most recent load, or null if it parsed cleanly. */
  get error(): string | null;
  /** The 1-based source line a parse error was attributed to, or null. */
  get errorLine(): number | null;
  /** The stable parser error code from the most recent failed load, or null. */
  get errorCode(): string | null;
  /** Whether the current document can render cleanly in blend/3D mode. */
  get voxelizable(): boolean;
  /** The index of the currently focused plane. */
  get currentIndex(): number;
  /** The active render mode. */
  get mode(): Mode;
  /** Whether playback is currently running. */
  get playing(): boolean;
  /** Focus a plane by index, clamped to range. */
  goTo(index: number): void;
  /** Toggle fullscreen for the element. */
  toggleFullscreen(): void;
  /** Replace the rendered document with new 3md source text. */
  setSource(source: string): void;
  /** Start auto-advancing through the planes. */
  play(): void;
  /** Stop auto-advancing. */
  pause(): void;
  /** Apply the current state to the DOM synchronously. */
  render(): void;
  connectedCallback(): void;
  disconnectedCallback(): void;
  attributeChangedCallback(name: string, oldValue: string | null, value: string | null): void;
}

declare global {
  interface HTMLElementTagNameMap {
    "three-md": ThreeMDElement;
  }
}
