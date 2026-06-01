class_name Kabsch

## Rigid-body point-cloud registration (Kabsch / Horn quaternion method).
##
## compute(src, dst) returns a Transform3D T such that T * src[i] ≈ dst[i].
## src = GLB-space positions, dst = LOCAL-space (headset) positions.
## Requires at least 3 non-collinear point pairs.

static func compute(src: Array[Vector3], dst: Array[Vector3]) -> Transform3D:
	var n := src.size()
	assert(n >= 3, "Kabsch requires at least 3 point pairs")
	assert(dst.size() == n, "Kabsch: src and dst must be the same length")

	# 1. Centroids
	var c_src := Vector3.ZERO
	var c_dst := Vector3.ZERO
	for i in n:
		c_src += src[i]
		c_dst += dst[i]
	c_src /= n
	c_dst /= n

	# 2. Cross-covariance matrix H (3×3, stored as 3 row Vector3s)
	#    H[row][col] = sum_k  (src[k] - c_src)[row] * (dst[k] - c_dst)[col]
	var H := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for k in n:
		var p := src[k] - c_src
		var q := dst[k] - c_dst
		H[0] += Vector3(p.x * q.x, p.x * q.y, p.x * q.z)
		H[1] += Vector3(p.y * q.x, p.y * q.y, p.y * q.z)
		H[2] += Vector3(p.z * q.x, p.z * q.y, p.z * q.z)

	# 3. Optimal quaternion via Horn's 4×4 symmetric N-matrix method.
	#    Uses Jacobi eigenvalue iteration (robust for any rotation magnitude,
	#    including near-180° rotations where power iteration fails).
	var rot := _horn_quaternion(H)

	# 4. Assemble Transform3D
	var basis := Basis(rot)
	var origin := c_dst - basis * c_src
	return Transform3D(basis, origin)


## Yaw-locked variant: solves for rotation around Y only (pitch and roll fixed to zero).
## Use when both src and dst are gravity-aligned (Y-up), which is always true for
## GLB↔ML2 calibration. Requires at least 2 non-coincident point pairs.
static func compute_yaw_locked(src: Array[Vector3], dst: Array[Vector3]) -> Transform3D:
	var n := src.size()
	assert(n >= 2, "Kabsch.compute_yaw_locked requires at least 2 point pairs")
	assert(dst.size() == n, "Kabsch.compute_yaw_locked: src and dst must be the same length")

	# 1. Centroids
	var c_src := Vector3.ZERO
	var c_dst := Vector3.ZERO
	for i in n:
		c_src += src[i]
		c_dst += dst[i]
	c_src /= n
	c_dst /= n

	# 2. Accumulate the 2D cross-covariance in the XZ plane.
	#    Summing (p.x*q.x + p.z*q.z) and (p.z*q.x - p.x*q.z) gives the
	#    least-squares optimal yaw angle across all N pairs.
	var scc := 0.0  # sum of cos terms
	var sss := 0.0  # sum of sin terms
	for k in n:
		var p := src[k] - c_src
		var q := dst[k] - c_dst
		scc += p.x * q.x + p.z * q.z
		sss += p.z * q.x - p.x * q.z

	var yaw := atan2(sss, scc)

	# 3. Build a pure Y-rotation basis from the yaw angle.
	var rot := Quaternion(Vector3.UP, yaw)
	var basis := Basis(rot)

	# 4. Translation from centroid constraint.
	var origin := c_dst - basis * c_src
	return Transform3D(basis, origin)



static func _horn_quaternion(H: Array) -> Quaternion:
	var Sxx: float = H[0].x; var Sxy: float = H[0].y; var Sxz: float = H[0].z
	var Syx: float = H[1].x; var Syy: float = H[1].y; var Syz: float = H[1].z
	var Szx: float = H[2].x; var Szy: float = H[2].y; var Szz: float = H[2].z

	# 4×4 symmetric N matrix (row-major, 16 floats).
	# Max eigenvector = optimal rotation quaternion in Horn's [w, x, y, z] order.
	var A: Array[float] = [
		 Sxx+Syy+Szz,  Syz-Szy,      Szx-Sxz,      Sxy-Syx,
		 Syz-Szy,      Sxx-Syy-Szz,  Sxy+Syx,       Szx+Sxz,
		 Szx-Sxz,      Sxy+Syx,     -Sxx+Syy-Szz,   Syz+Szy,
		 Sxy-Syx,      Szx+Sxz,      Syz+Szy,       -Sxx-Syy+Szz,
	]

	# Eigenvector matrix V (row-major), initialised to identity.
	# Column i of V will hold the i-th eigenvector after convergence.
	var V: Array[float] = [
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		0.0, 0.0, 0.0, 1.0,
	]

	# Jacobi sweeps - robust for any rotation, including near-180°.
	for _sweep in 50:
		# Find the off-diagonal element with the largest absolute value.
		var max_val := 0.0
		var p := 0
		var q := 1
		for i in 4:
			for j in range(i + 1, 4):
				var v := absf(A[i * 4 + j])
				if v > max_val:
					max_val = v
					p = i
					q = j

		if max_val < 1e-10:
			break  # converged

		# Jacobi rotation parameters.
		var apq: float = A[p * 4 + q]
		var tau: float = (A[q * 4 + q] - A[p * 4 + p]) / (2.0 * apq)
		var t:   float = 1.0 / (absf(tau) + sqrt(1.0 + tau * tau))
		if tau < 0.0:
			t = -t
		var c: float = 1.0 / sqrt(1.0 + t * t)
		var s: float = t * c

		# Update diagonal and zero out A[p,q].
		A[p * 4 + p] -= t * apq
		A[q * 4 + q] += t * apq
		A[p * 4 + q] = 0.0
		A[q * 4 + p] = 0.0

		# Update remaining rows/columns of A.
		for r in 4:
			if r == p or r == q:
				continue
			var arp: float = A[r * 4 + p]
			var arq: float = A[r * 4 + q]
			A[r * 4 + p] = c * arp - s * arq
			A[p * 4 + r] = A[r * 4 + p]
			A[r * 4 + q] = s * arp + c * arq
			A[q * 4 + r] = A[r * 4 + q]

		# Accumulate the rotation into V.
		for r in 4:
			var vrp: float = V[r * 4 + p]
			var vrq: float = V[r * 4 + q]
			V[r * 4 + p] = c * vrp - s * vrq
			V[r * 4 + q] = s * vrp + c * vrq

	# Find the column of V corresponding to the largest eigenvalue.
	var best := 0
	for i in range(1, 4):
		if A[i * 4 + i] > A[best * 4 + best]:
			best = i

	# Column `best` of V is the eigenvector in Horn's [w, x, y, z] order.
	# Godot Quaternion constructor takes (x, y, z, w).
	return Quaternion(
		V[1 * 4 + best],
		V[2 * 4 + best],
		V[3 * 4 + best],
		V[0 * 4 + best]
	).normalized()
