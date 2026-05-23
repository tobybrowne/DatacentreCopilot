import { createServer } from 'http'
import { init as initRecast, importNavMesh, NavMeshQuery } from 'recast-navigation'
import { NavMeshHelper } from '@recast-navigation/three'

const PORT = parseInt(process.env.DETOUR_PORT ?? '7654')

await initRecast()
console.log('[detour] Recast initialised')

function snapToNavMesh(query, pos) {
  const tight = query.findClosestPoint(pos, { halfExtents: { x: 0.3, y: 5.0, z: 0.3 } })
  if (tight.success) return tight
  const wide = query.findClosestPoint(pos, { halfExtents: { x: 3.0, y: 5.0, z: 3.0 } })
  if (wide.success) return wide
  return query.findClosestPoint(pos, { halfExtents: { x: 8.0, y: 5.0, z: 8.0 } })
}

const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200)
    res.end('ok')
    return
  }

  if (req.method !== 'POST' || !req.url.startsWith('/query')) {
    res.writeHead(404)
    res.end()
    return
  }

  const url = new URL(req.url, `http://127.0.0.1:${PORT}`)
  const x1 = Number(url.searchParams.get('x1'))
  const y1 = Number(url.searchParams.get('y1'))
  const z1 = Number(url.searchParams.get('z1'))
  const x2 = Number(url.searchParams.get('x2'))
  const y2 = Number(url.searchParams.get('y2'))
  const z2 = Number(url.searchParams.get('z2'))

  const chunks = []
  req.on('data', chunk => chunks.push(chunk))
  req.on('end', () => {
    try {
      const navmeshData = new Uint8Array(Buffer.concat(chunks))
      const { navMesh } = importNavMesh(navmeshData)
      if (!navMesh) throw new Error('Failed to import navmesh')

      const query = new NavMeshQuery(navMesh)

      const { point: start, success: startOk } = snapToNavMesh(query, { x: x1, y: y1, z: z1 })
      const { point: end,   success: endOk   } = snapToNavMesh(query, { x: x2, y: y2, z: z2 })

      if (!startOk || !endOk) throw new Error('Could not snap one or both points to navmesh')

      const { path } = query.computePath(start, end)

      const helper = new NavMeshHelper(navMesh)
      const geo = helper.mesh.geometry
      const posAttr = geo.attributes.position
      const verts = []
      for (let i = 0; i < posAttr.count; i++) {
        verts.push([posAttr.getX(i), posAttr.getY(i), posAttr.getZ(i)])
      }
      const faces = []
      const idx = geo.index
      if (idx) {
        for (let i = 0; i < idx.count; i += 3) {
          faces.push([idx.getX(i), idx.getX(i + 1), idx.getX(i + 2)])
        }
      }

      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ path, verts, faces, snapStart: start, snapEnd: end }))
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: e.message }))
    }
  })
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[detour] listening on 127.0.0.1:${PORT}`)
})
