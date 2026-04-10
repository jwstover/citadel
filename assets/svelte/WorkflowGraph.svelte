<script>
  import { SvelteFlow, Controls, Background } from '@xyflow/svelte';
  import dagre from '@dagrejs/dagre';
  import WorkflowNode from './WorkflowNode.svelte';
  import DetailPanel from './DetailPanel.svelte';
  import '@xyflow/svelte/dist/style.css';

  let { initialNodes = [], initialEdges = [] } = $props();

  const NODE_WIDTH = 200;
  const NODE_HEIGHT = 80;

  let selectedNode = $state(null);

  function getLayoutedElements(rawNodes, rawEdges) {
    const g = new dagre.graphlib.Graph();
    g.setDefaultEdgeLabel(() => ({}));
    g.setGraph({ rankdir: 'TB', nodesep: 60, ranksep: 100 });

    for (const node of rawNodes) {
      g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT });
    }

    for (const edge of rawEdges) {
      g.setEdge(edge.source, edge.target);
    }

    dagre.layout(g);

    const layoutedNodes = rawNodes.map((node) => {
      const pos = g.node(node.id);
      return {
        ...node,
        position: {
          x: pos.x - NODE_WIDTH / 2,
          y: pos.y - NODE_HEIGHT / 2,
        },
      };
    });

    return { nodes: layoutedNodes, edges: rawEdges };
  }

  function styleEdges(edges, nodes) {
    const runningNodeIds = new Set(
      nodes.filter((n) => n.data.status === 'running').map((n) => n.id)
    );

    return edges.map((edge) => {
      if (runningNodeIds.has(edge.target)) {
        return {
          ...edge,
          animated: true,
          style: 'stroke: oklch(77% 0.152 181.912); stroke-width: 2px;',
        };
      }
      return {
        ...edge,
        style: 'stroke: oklch(30% 0 0); stroke-width: 1.5px;',
      };
    });
  }

  function handleNodeClick(_event, node) {
    selectedNode = node;
  }

  function handlePaneClick() {
    selectedNode = null;
  }

  function closePanel() {
    selectedNode = null;
  }

  const nodeTypes = { workflow: WorkflowNode };
  const layout = getLayoutedElements(initialNodes, initialEdges);
  const styledEdges = styleEdges(layout.edges, initialNodes);
</script>

<div class="workflow-graph-container">
  <SvelteFlow
    nodes={layout.nodes}
    edges={styledEdges}
    {nodeTypes}
    fitView
    onnodeclick={handleNodeClick}
    onpaneclick={handlePaneClick}
    proOptions={{ hideAttribution: true }}
    colorMode="dark"
  >
    <Controls />
    <Background />
  </SvelteFlow>

  <DetailPanel node={selectedNode} onclose={closePanel} />
</div>

<style>
  .workflow-graph-container {
    width: 100%;
    height: 100%;
    position: relative;
  }

  :global(.svelte-flow) {
    background: oklch(10% 0 150) !important;
  }

  :global(.svelte-flow__edge-path) {
    stroke: oklch(30% 0 0);
  }

  :global(.svelte-flow__edge-text) {
    fill: oklch(60% 0 0) !important;
    font-size: 11px !important;
  }

  :global(.svelte-flow__edge-textbg) {
    fill: oklch(10% 0 150) !important;
  }

  :global(.svelte-flow__controls) {
    background: oklch(15% 0 150) !important;
    border: 1px solid oklch(25% 0 0) !important;
    border-radius: 6px !important;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3) !important;
  }

  :global(.svelte-flow__controls button) {
    background: oklch(15% 0 150) !important;
    border-color: oklch(25% 0 0) !important;
    color: oklch(70% 0 0) !important;
    fill: oklch(70% 0 0) !important;
  }

  :global(.svelte-flow__controls button:hover) {
    background: oklch(20% 0 150) !important;
  }

  :global(.svelte-flow__controls button svg) {
    fill: oklch(70% 0 0) !important;
  }

  :global(.svelte-flow__background pattern circle) {
    fill: oklch(18% 0 0) !important;
  }
</style>
