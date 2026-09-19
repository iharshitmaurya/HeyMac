import Foundation

public struct FaceEmbedding: Equatable {
    public let vector: [Float]
    public init(vector: [Float]) {
        self.vector = vector
    }
}

public enum EmbeddingMath {
    public static func cosineSimilarity(_ a: FaceEmbedding, _ b: FaceEmbedding) -> Float {
        precondition(a.vector.count == b.vector.count, "embeddings must be the same dimension")
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.vector.count {
            dot += a.vector[i] * b.vector[i]
            normA += a.vector[i] * a.vector[i]
            normB += b.vector[i] * b.vector[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    public static func normalized(_ embedding: FaceEmbedding) -> FaceEmbedding {
        let norm = embedding.vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return embedding }
        return FaceEmbedding(vector: embedding.vector.map { $0 / norm })
    }

    public static func centroid(of embeddings: [FaceEmbedding]) -> FaceEmbedding {
        precondition(!embeddings.isEmpty, "centroid requires at least one embedding")
        let dimension = embeddings[0].vector.count
        var sum = [Float](repeating: 0, count: dimension)
        for embedding in embeddings {
            precondition(embedding.vector.count == dimension, "all embeddings must share a dimension")
            for i in 0..<dimension { sum[i] += embedding.vector[i] }
        }
        let count = Float(embeddings.count)
        return FaceEmbedding(vector: sum.map { $0 / count })
    }
}
