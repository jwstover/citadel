<script>
  import { Handle, Position } from '@xyflow/svelte';

  let { data } = $props();

  const showTarget = data.nodeType !== 'start';
  const showSource = data.nodeType !== 'end';
  const isRunning = data.status === 'running';

  const typeIcons = {
    start: '▶',
    end: '■',
    action: '⚡',
    decision: '◆',
  };
</script>

{#if showTarget}
  <Handle type="target" position={Position.Top} class="handle" />
{/if}

<div
  class="workflow-node"
  class:running={isRunning}
  data-type={data.nodeType}
>
  <div class="node-header">
    <span class="type-badge" data-type={data.nodeType}>
      {typeIcons[data.nodeType] || '●'}
    </span>
    <span class="node-label">{data.label}</span>
  </div>
  {#if data.description}
    <div class="node-desc">{data.description}</div>
  {/if}
</div>

{#if showSource}
  <Handle type="source" position={Position.Bottom} class="handle" />
{/if}

<style>
  @keyframes runner-pulse {
    0%, 100% {
      box-shadow:
        0 0 4px rgba(148, 226, 213, 0.3),
        0 0 12px rgba(148, 226, 213, 0.15);
    }
    50% {
      box-shadow:
        0 0 8px rgba(148, 226, 213, 0.5),
        0 0 24px rgba(148, 226, 213, 0.25),
        0 0 40px rgba(148, 226, 213, 0.1);
    }
  }

  .workflow-node {
    padding: 10px 16px;
    border-radius: 6px;
    min-width: 160px;
    text-align: left;
    font-family: system-ui, -apple-system, sans-serif;
    background: oklch(15% 0 150);
    color: oklch(93% 0.005 50);
    border: 1.5px solid oklch(25% 0 0);
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.4);
    cursor: pointer;
    transition: border-color 0.2s ease, box-shadow 0.2s ease;
  }

  .workflow-node:hover {
    border-color: oklch(35% 0 0);
  }

  .workflow-node[data-type='start'] {
    border-color: oklch(77% 0.152 181.912);
    border-radius: 9999px;
    text-align: center;
    padding: 10px 24px;
  }
  .workflow-node[data-type='start']:hover {
    border-color: oklch(85% 0.152 181.912);
  }

  .workflow-node[data-type='end'] {
    border-color: oklch(83.92% 0.0901 136.87);
    border-radius: 9999px;
    text-align: center;
    padding: 10px 24px;
  }
  .workflow-node[data-type='end']:hover {
    border-color: oklch(90% 0.0901 136.87);
  }

  .workflow-node[data-type='action'] {
    border-color: oklch(25% 0 0);
  }

  .workflow-node[data-type='decision'] {
    border-color: oklch(80.39% 0.1148 241.68);
  }
  .workflow-node[data-type='decision']:hover {
    border-color: oklch(88% 0.1148 241.68);
  }

  .workflow-node.running {
    border-color: oklch(77% 0.152 181.912);
    animation: runner-pulse 2.5s ease-in-out infinite;
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

  .type-badge {
    font-size: 10px;
    width: 20px;
    height: 20px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    flex-shrink: 0;
    background: oklch(20% 0 150);
    color: oklch(80% 0 0);
  }

  .type-badge[data-type='start'] {
    background: oklch(77% 0.152 181.912 / 0.15);
    color: oklch(77% 0.152 181.912);
  }

  .type-badge[data-type='end'] {
    background: oklch(83.92% 0.0901 136.87 / 0.15);
    color: oklch(83.92% 0.0901 136.87);
  }

  .type-badge[data-type='action'] {
    background: oklch(25% 0 0);
    color: oklch(80% 0 0);
  }

  .type-badge[data-type='decision'] {
    background: oklch(80.39% 0.1148 241.68 / 0.15);
    color: oklch(80.39% 0.1148 241.68);
  }

  .node-label {
    font-weight: 600;
    font-size: 13px;
    line-height: 1.2;
  }

  .node-desc {
    font-size: 11px;
    opacity: 0.55;
    margin-top: 4px;
    line-height: 1.3;
    padding-left: 26px;
  }

  [data-type='start'] .node-desc,
  [data-type='end'] .node-desc {
    padding-left: 0;
  }

  :global(.handle) {
    width: 8px !important;
    height: 8px !important;
    background: oklch(25% 0 0) !important;
    border: 1.5px solid oklch(40% 0 0) !important;
    border-radius: 50% !important;
  }
</style>
