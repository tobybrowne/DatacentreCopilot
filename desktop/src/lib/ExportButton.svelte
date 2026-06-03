<script lang="ts">
  // Camera-icon overlay button for exporting the current 3D view to PNG.
  // Positioned bottom-right of a relatively-positioned container by default;
  // pass `style` to nudge it (e.g. "bottom: 44px" to sit above another button).
  import { Camera } from 'lucide-svelte'

  let { onclick, style = '' }: { onclick: () => void; style?: string } = $props()
</script>

<button class="export-btn" {style} {onclick} title="Export PNG" aria-label="Export PNG">
  <Camera size={16} />
</button>

<style>
  .export-btn {
    position: absolute;
    bottom: 12px;
    right: 12px;
    padding: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.4);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 4px;
    cursor: pointer;
  }
  .export-btn:hover {
    background: rgba(0, 0, 0, 0.6);
  }
</style>
