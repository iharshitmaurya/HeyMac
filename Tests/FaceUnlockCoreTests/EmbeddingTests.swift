import Testing
@testable import FaceUnlockCore

@Test func identicalVectorsHaveSimilarityOne() {
    let a = FaceEmbedding(vector: [1, 0, 0])
    let b = FaceEmbedding(vector: [1, 0, 0])
    #expect(abs(EmbeddingMath.cosineSimilarity(a, b) - 1.0) < 0.0001)
}

@Test func orthogonalVectorsHaveSimilarityZero() {
    let a = FaceEmbedding(vector: [1, 0])
    let b = FaceEmbedding(vector: [0, 1])
    #expect(abs(EmbeddingMath.cosineSimilarity(a, b)) < 0.0001)
}

@Test func oppositeVectorsHaveSimilarityNegativeOne() {
    let a = FaceEmbedding(vector: [1, 0])
    let b = FaceEmbedding(vector: [-1, 0])
    #expect(abs(EmbeddingMath.cosineSimilarity(a, b) - (-1.0)) < 0.0001)
}

@Test func centroidAveragesComponentwise() {
    let embeddings = [FaceEmbedding(vector: [1, 0]), FaceEmbedding(vector: [0, 1])]
    let result = EmbeddingMath.centroid(of: embeddings)
    #expect(abs(result.vector[0] - 0.5) < 0.0001)
    #expect(abs(result.vector[1] - 0.5) < 0.0001)
}

@Test func centroidOfSingleEmbeddingIsItself() {
    let embeddings = [FaceEmbedding(vector: [3, 4])]
    let result = EmbeddingMath.centroid(of: embeddings)
    #expect(result.vector == [3, 4])
}
