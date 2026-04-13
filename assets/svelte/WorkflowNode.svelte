<script>
  import { Handle, Position } from '@xyflow/svelte';

  let { data } = $props();

  const showTarget = data.nodeType !== 'start';
  const showSource = data.nodeType !== 'end';
  const isRunning = data.status === 'running';
  const isComplete = data.status === 'complete';
  const isError = data.status === 'error';
</script>

{#if showTarget}
  <Handle id="left" type="target" position={Position.Left} class="handle" />
  <Handle id="bottom-target" type="target" position={Position.Bottom} class="handle handle-loop" />
{/if}

<div
  class="workflow-node"
  data-type={data.nodeType}
>
  <div class="node-header">
    {#if data.nodeType === 'start'}
      <span class="type-icon">
        <svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor"><polygon points="2,0 10,5 2,10" /></svg>
      </span>
    {:else if data.nodeType === 'end'}
      <span class="type-icon">
        <svg width="8" height="8" viewBox="0 0 8 8" fill="currentColor"><rect x="0" y="0" width="8" height="8" rx="1" /></svg>
      </span>
    {:else if data.nodeType === 'decision'}
      <span class="type-icon">
        <svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor"><polygon points="5,0 10,5 5,10 0,5" /></svg>
      </span>
    {/if}
    <span class="node-label">{data.label}</span>
    {#if isRunning}
      <span class="status-dot running"></span>
    {:else if isComplete}
      <span class="status-dot complete"></span>
    {:else if isError}
      <span class="status-dot error"></span>
    {/if}
  </div>
  {#if data.description}
    <div class="node-desc">{data.description}</div>
  {/if}
</div>

{#if showSource}
  <Handle id="right" type="source" position={Position.Right} class="handle" />
  <Handle id="bottom-source" type="source" position={Position.Bottom} class="handle handle-loop" />
{/if}

<style>
  @keyframes pulse {
    0%, 100% { opacity: 0.4; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.3); }
  }

  .workflow-node {
    padding: 10px 16px;
    border-radius: 6px;
    min-width: 160px;
    text-align: left;
    font-family: system-ui, -apple-system, sans-serif;
    background: oklch(15% 0 150);
    color: oklch(90% 0 0);
    border: 1px solid oklch(25% 0 0);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
    cursor: pointer;
    transition: border-color 0.15s ease, background 0.15s ease;
  }

  .workflow-node:hover {
    border-color: oklch(35% 0 0);
    background: oklch(17% 0 150);
  }

  .workflow-node[data-type='start'],
  .workflow-node[data-type='end'] {
    border-radius: 9999px;
    text-align: center;
    padding: 10px 24px;
  }

  .node-header {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  [data-type='start'] .node-header,
  [data-type='end'] .node-header {
    justify-content: center;
  }

  .type-icon {
    width: 16px;
    height: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    color: oklch(55% 0 0);
  }

  .node-label {
    font-weight: 600;
    font-size: 13px;
    line-height: 1.2;
  }

  .status-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    flex-shrink: 0;
    margin-left: auto;
  }

  .status-dot.running {
    background: oklch(75% 0.15 160);
    animation: pulse 2s ease-in-out infinite;
  }

  .status-dot.complete {
    background: oklch(70% 0.12 145);
  }

  .status-dot.error {
    background: oklch(65% 0.2 25);
  }

  .node-desc {
    font-size: 11px;
    color: oklch(55% 0 0);
    margin-top: 4px;
    line-height: 1.3;
  }

  :global(.handle) {
    width: 6px !important;
    height: 6px !important;
    background: oklch(25% 0 0) !important;
    border: 1px solid oklch(40% 0 0) !important;
    border-radius: 50% !important;
  }

  :global(.handle-loop) {
    width: 5px !important;
    height: 5px !important;
    opacity: 0.5;
  }
</style>
