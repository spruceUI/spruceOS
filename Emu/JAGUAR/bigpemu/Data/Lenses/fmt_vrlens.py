from inc_noesis import *

#this is a noesis script to read/write VR lens files

def registerNoesisTypes():
	handle = noesis.register("VR Lens Model", ".vrlens")
	noesis.setHandlerTypeCheck(handle, vrlensCheckType)
	noesis.setHandlerLoadModel(handle, vrlensLoadModel)
	noesis.setHandlerWriteModel(handle, vrlensWriteModel)
	return 1

VRLENS_HEADER = 0x539474
VRLENS_VERSION = 0x1010
VERTEX_SIZE = 20

def vrlensCheckType(data):
	if len(data) < 8:
		return 0
	id, ver = noeUnpack("<II", data[:8])
	if id != VRLENS_HEADER or ver != VRLENS_VERSION:
		return 0
	return 1

def vrlensLoadModel(data, mdlList):
	bs = NoeBitStream(data)
	bs.readInt()
	bs.readInt()
	vertCount = bs.readInt()
	indexCount = bs.readInt()
	
	vertexData = data[bs.tell():]

	ctx = rapi.rpgCreateContext()
	rapi.rpgSetMaterial("vrlens")
	rapi.rpgBindPositionBufferOfs(vertexData, noesis.RPGEODATA_FLOAT, VERTEX_SIZE, 0)
	rapi.rpgBindUV1BufferOfs(vertexData, noesis.RPGEODATA_FLOAT, VERTEX_SIZE, 12)
	rapi.rpgCommitTriangles(vertexData[vertCount * VERTEX_SIZE:], noesis.RPGEODATA_INT, indexCount, noesis.RPGEO_TRIANGLE, 1)
	rapi.rpgOptimize()
	mdl = rapi.rpgConstructModel()
	mdlList.append(mdl)

	return 1

def vrlensWriteModel(mdl, bs):
	bs.writeInt(VRLENS_HEADER)
	bs.writeInt(VRLENS_VERSION)

	totalPosCount = 0
	totalIndexCount = 0
	for mesh in mdl.meshes:
		totalPosCount += len(mesh.positions)
		totalIndexCount += len(mesh.indices)

	bs.writeInt(totalPosCount)
	bs.writeInt(totalIndexCount)
	#we're dealing with 32-bit indices, so we collapse geometry across all meshes into a single list
	baseIndices = []
	currentBaseIndex = 0
	for mesh in mdl.meshes:
		posCount = len(mesh.positions)
		baseIndices.append(currentBaseIndex)
		currentBaseIndex += posCount
		for vcmpIndex in range(posCount):
			bs.writeBytes(mesh.positions[vcmpIndex].toBytes())
			#don't need z
			uv = mesh.uvs[vcmpIndex]
			bs.writeFloat(uv[0])
			bs.writeFloat(uv[1])
	for meshIndex in range(len(mdl.meshes)):
		mesh = mdl.meshes[meshIndex]
		baseIndex = baseIndices[meshIndex]
		for idx in mesh.indices:
			bs.writeInt(baseIndex + idx)
	return 1
