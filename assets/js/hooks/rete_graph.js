// Draws the beta network pushed by EngineLive ("graph" events) with an ELK
// layered layout, and highlights the selection ("select" events).
//
// The SVG is managed here, so the hook element has phx-update="ignore".

import ELK from 'elkjs/lib/elk.bundled.js'

const SVG_NS = 'http://www.w3.org/2000/svg'

const NODE = {
  paddingX: 12,
  paddingTop: 8,
  titleHeight: 16,
  detailHeight: 18,
  paddingBottom: 8,
  minWidth: 72,
  maxDetailChars: 56
}

const TITLE_FONT = '600 11px ui-sans-serif, system-ui, sans-serif'
const DETAIL_FONT = '12px ui-monospace, SFMono-Regular, Menlo, monospace'

const LAYOUT_OPTIONS = {
  'elk.algorithm': 'layered',
  'elk.direction': 'DOWN',
  'elk.edgeRouting': 'SPLINES',
  'elk.layered.spacing.nodeNodeBetweenLayers': '44',
  'elk.spacing.nodeNode': '28',
  'elk.layered.nodePlacement.strategy': 'NETWORK_SIMPLEX',
  'elk.layered.crossingMinimization.semiInteractive': 'true'
}

const elk = new ELK()

function svg(tag, attrs = {}, parent = null) {
  const el = document.createElementNS(SVG_NS, tag)
  for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value)
  if (parent) parent.appendChild(el)
  return el
}

function truncate(text, max) {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text
}

const measureContext = document.createElement('canvas').getContext('2d')

function textWidth(text, font) {
  measureContext.font = font
  return measureContext.measureText(text).width
}

function nodeSize(node) {
  const title = node.title.toUpperCase()
  const detail = node.detail ? truncate(node.detail, NODE.maxDetailChars) : null
  const width = Math.max(
    NODE.minWidth,
    textWidth(title, TITLE_FONT) + 44,
    detail ? textWidth(detail, DETAIL_FONT) : 0
  )
  const height =
    NODE.paddingTop + NODE.titleHeight + (detail ? NODE.detailHeight : 0) + NODE.paddingBottom
  return { width: Math.ceil(width + NODE.paddingX * 2), height, detail }
}

function edgePath(section) {
  const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint]
  if (points.length === 2) {
    return `M${points[0].x},${points[0].y} L${points[1].x},${points[1].y}`
  }
  // ELK spline routing returns control points for consecutive cubic curves.
  let d = `M${points[0].x},${points[0].y}`
  let i = 1
  while (i + 2 < points.length) {
    const [c1, c2, p] = [points[i], points[i + 1], points[i + 2]]
    d += ` C${c1.x},${c1.y} ${c2.x},${c2.y} ${p.x},${p.y}`
    i += 3
  }
  for (; i < points.length; i++) d += ` L${points[i].x},${points[i].y}`
  return d
}

export default {
  mounted() {
    this.view = { x: 0, y: 0, k: 1 }
    this.selection = { rule: null, node: null }
    this.nodes = new Map()
    this.layoutId = 0
    this.hasFitted = false

    this.svg = svg(
      'svg',
      { class: 'graph-svg', role: 'img', 'aria-label': 'Rete network' },
      this.el
    )
    const defs = svg('defs', {}, this.svg)
    const marker = svg(
      'marker',
      {
        id: 'graph-arrow',
        viewBox: '0 0 10 10',
        refX: '9',
        refY: '5',
        markerWidth: '7',
        markerHeight: '7',
        orient: 'auto-start-reverse'
      },
      defs
    )
    svg('path', { d: 'M 0 0 L 10 5 L 0 10 z', class: 'graph-arrowhead' }, marker)
    this.viewport = svg('g', { class: 'graph-viewport' }, this.svg)
    this.edgeLayer = svg('g', { class: 'graph-edges' }, this.viewport)
    this.nodeLayer = svg('g', { class: 'graph-nodes' }, this.viewport)

    this.installPanZoom()
    this.el.addEventListener('wongi:fit', () => this.fit(true))
    this.el.addEventListener('wongi:zoom', (e) => this.zoomBy(e.detail.factor))

    this.resizeObserver = new ResizeObserver(() => {
      if (!this.hasFitted) this.fit(false)
    })
    this.resizeObserver.observe(this.el)

    this.handleEvent('graph', (graph) => this.render(graph))
    this.handleEvent('select', (selection) => {
      this.selection = selection
      this.applySelection()
    })
  },

  destroyed() {
    this.resizeObserver?.disconnect()
  },

  async render(graph) {
    const layoutId = ++this.layoutId
    const sizes = new Map(graph.nodes.map((node) => [node.id, nodeSize(node)]))

    const layout = await elk.layout({
      id: 'root',
      layoutOptions: LAYOUT_OPTIONS,
      children: graph.nodes.map((node) => ({
        id: node.id,
        width: sizes.get(node.id).width,
        height: sizes.get(node.id).height
      })),
      edges: graph.edges.map((edge, index) => ({
        id: `e${index}`,
        sources: [edge.source],
        targets: [edge.target]
      }))
    })

    // A newer graph arrived while this one was being laid out.
    if (layoutId !== this.layoutId) return

    const positions = new Map(layout.children.map((child) => [child.id, child]))
    this.nodes = new Map(graph.nodes.map((node) => [node.id, node]))
    this.bounds = { width: layout.width, height: layout.height }

    this.edgeLayer.replaceChildren()
    layout.edges.forEach((laidOut, index) => {
      const edge = graph.edges[index]
      for (const section of laidOut.sections || []) {
        svg(
          'path',
          {
            d: edgePath(section),
            class: `graph-edge graph-edge-${edge.kind}`,
            'data-source': edge.source,
            'data-target': edge.target,
            'marker-end': 'url(#graph-arrow)'
          },
          this.edgeLayer
        )
      }
    })

    this.nodeLayer.replaceChildren()
    for (const node of graph.nodes) {
      const { x, y, width, height } = positions.get(node.id)
      const { detail } = sizes.get(node.id)
      const g = svg(
        'g',
        {
          class: `graph-node node-${node.type}`,
          transform: `translate(${x},${y})`,
          'data-id': node.id,
          tabindex: '0',
          role: 'button',
          'aria-label': `${node.title}${node.detail ? `: ${node.detail}` : ''}`
        },
        this.nodeLayer
      )
      svg('rect', { class: 'graph-node-box', width, height, rx: '8' }, g)
      svg('rect', { class: 'graph-node-accent', width: '4', height, rx: '2' }, g)

      const title = svg(
        'text',
        { class: 'graph-node-title', x: NODE.paddingX, y: NODE.paddingTop + 11 },
        g
      )
      title.textContent = node.title.toUpperCase()

      if (node.tokens > 0) {
        const badge = svg(
          'text',
          { class: 'graph-node-tokens', x: width - NODE.paddingX, y: NODE.paddingTop + 11 },
          g
        )
        badge.textContent = `${node.tokens}`
        svg('title', {}, badge).textContent = `${node.tokens} token(s)`
      }

      if (detail) {
        const text = svg(
          'text',
          {
            class: 'graph-node-detail',
            x: NODE.paddingX,
            y: NODE.paddingTop + NODE.titleHeight + 13
          },
          g
        )
        text.textContent = detail
      }
      if (node.detail && detail !== node.detail) svg('title', {}, g).textContent = node.detail

      g.addEventListener('click', (e) => {
        e.stopPropagation()
        this.pushEvent('select_node', { id: node.id })
      })
      g.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          this.pushEvent('select_node', { id: node.id })
        }
      })
    }

    this.applySelection()
    if (!this.hasFitted) this.fit(false)
  },

  applySelection() {
    const { rule, node: selectedId } = this.selection
    const inRule = (id) => rule === null || (this.nodes.get(id)?.rules || []).includes(rule)

    for (const g of this.nodeLayer.querySelectorAll('.graph-node')) {
      const id = g.dataset.id
      g.classList.toggle('dimmed', !inRule(id))
      g.classList.toggle('selected', id === selectedId)
    }
    for (const path of this.edgeLayer.querySelectorAll('.graph-edge')) {
      const active = inRule(path.dataset.source) && inRule(path.dataset.target)
      path.classList.toggle('dimmed', !active)
    }
  },

  // Pan with the pointer, zoom with the wheel or the toolbar.
  installPanZoom() {
    let drag = null

    this.svg.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || e.target.closest('.graph-node')) return
      drag = { x: e.clientX, y: e.clientY, view: { ...this.view }, moved: false }
      this.svg.setPointerCapture(e.pointerId)
    })
    this.svg.addEventListener('pointermove', (e) => {
      if (!drag) return
      const dx = e.clientX - drag.x
      const dy = e.clientY - drag.y
      if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true
      this.setView({ ...drag.view, x: drag.view.x + dx, y: drag.view.y + dy })
    })
    this.svg.addEventListener('pointerup', (e) => {
      if (drag && !drag.moved && this.selection.node !== null) {
        this.pushEvent('select_node', { id: null })
      }
      drag = null
      this.svg.releasePointerCapture(e.pointerId)
    })
    this.svg.addEventListener(
      'wheel',
      (e) => {
        e.preventDefault()
        const rect = this.svg.getBoundingClientRect()
        const factor = Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.002))
        this.zoomAt(factor, e.clientX - rect.left, e.clientY - rect.top)
      },
      { passive: false }
    )
  },

  zoomBy(factor) {
    const rect = this.svg.getBoundingClientRect()
    this.zoomAt(factor, rect.width / 2, rect.height / 2, true)
  },

  zoomAt(factor, cx, cy, animate = false) {
    const k = Math.min(3, Math.max(0.15, this.view.k * factor))
    const ratio = k / this.view.k
    this.setView(
      { k, x: cx - (cx - this.view.x) * ratio, y: cy - (cy - this.view.y) * ratio },
      animate
    )
  },

  fit(animate) {
    const rect = this.svg.getBoundingClientRect()
    if (!this.bounds || rect.width === 0 || rect.height === 0) return
    const margin = 32
    const k = Math.min(
      1.25,
      (rect.width - margin * 2) / this.bounds.width,
      (rect.height - margin * 2) / this.bounds.height
    )
    const x = (rect.width - this.bounds.width * k) / 2
    const y = Math.max(margin, (rect.height - this.bounds.height * k) / 2)
    this.setView({ k, x, y }, animate)
    this.hasFitted = true
  },

  // A CSS transform rather than the attribute, so that it can transition.
  setView(view, animate = false) {
    this.view = view
    this.viewport.classList.toggle('animated', animate)
    this.viewport.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.k})`
  }
}
