import Foundation

final class PersistentEvaluationStorage: EvaluationReadStorage, EvaluationWriteStorage, Sendable {

    private let keyValueStorage: PersistentKeyValueStorage

    init(keyValueStorage: PersistentKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    // MARK: - EvaluationWriteStorage

    func upsert(change: EvaluationChange) async throws {
        var evaluationsMap = await readDTO(for: change.target)?.evaluations ?? [:]

        for evaluation in change.evaluations {
            evaluationsMap[evaluation.flag] = EvaluationResultDTO(treatment: evaluation.treatment, changeNumber: evaluation.changeNumber, config: evaluation.config, sets: evaluation.flagSets)
        }

        let dto = EvaluationChangeDTO(changeNumber: change.changeNumber, evaluations: evaluationsMap)

        let data = try Json.encode(dto)
        try await keyValueStorage.write(key: storageKey(for: change.target), value: data)
    }

    func clear(target: Target) async {
        try? await keyValueStorage.remove(key: storageKey(for: target))
    }

    // MARK: - EvaluationReadStorage

    func get(flag: String, target: Target) async -> EvaluationResult? {
        guard let resultDTO = await readDTO(for: target)?.evaluations?[flag] else {
            return nil
        }
        return resultDTO.toEvaluationResult(flag: flag)
    }

    func get(flags: [String], target: Target) async -> [EvaluationResult] {
        guard let evaluations = await readDTO(for: target)?.evaluations else {
            return []
        }
        return flags.compactMap { flag in
            evaluations[flag]?.toEvaluationResult(flag: flag)
        }
    }

    func get(byFlagSets flagSets: [String], target: Target) async -> [EvaluationResult] {
        guard let evaluations = await readDTO(for: target)?.evaluations else {
            return []
        }
        let requestedSets = Set(flagSets)
        return evaluations.compactMap { flag, resultDTO in
            guard !Set(resultDTO.sets ?? []).isDisjoint(with: requestedSets) else {
                return nil
            }
            return resultDTO.toEvaluationResult(flag: flag)
        }
    }

    func getFlagNames(target: Target) async -> [String] {
        guard let evaluations = await readDTO(for: target)?.evaluations else {
            return []
        }
        return Array(evaluations.keys)
    }

    func lastChangeNumber(target: Target) async -> Int64? {
        await readDTO(for: target)?.changeNumber
    }

    // MARK: - Private

    private func readDTO(for target: Target) async -> EvaluationChangeDTO? {
        guard let data = await keyValueStorage.read(key: storageKey(for: target)) else {
            return nil
        }
        return try? Json.decode(from: data, to: EvaluationChangeDTO.self)
    }

    private func storageKey(for target: Target) -> String {
        "evaluations.\(target.matchingKey)"
    }
}
