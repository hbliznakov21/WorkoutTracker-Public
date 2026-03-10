import Foundation
import UIKit
import ImageIO

@Observable
@MainActor
final class PhotoStore {
    static let shared = PhotoStore()

    var entries: [PhotoEntry] = []

    private let entriesKey = "photo_entries"
    private let photosDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        photosDir = docs.appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        loadEntries()
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([PhotoEntry].self, from: data) else { return }
        entries = decoded
    }

    private static let maxEntries = 100

    private func saveEntries() {
        // Trim oldest entries if exceeding limit
        if entries.count > Self.maxEntries {
            let overflow = entries.prefix(entries.count - Self.maxEntries)
            for entry in overflow {
                let fileURL = photosDir.appendingPathComponent(entry.imagePath)
                try? FileManager.default.removeItem(at: fileURL)
            }
            entries = Array(entries.suffix(Self.maxEntries))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    // MARK: - Public API

    func savePhoto(image: UIImage, pose: String, date: String) {
        let id = UUID()
        let filename = "\(date)_\(pose)_\(id.uuidString).jpg"
        let fileURL = photosDir.appendingPathComponent(filename)

        guard let jpegData = image.jpegData(compressionQuality: 0.8),
              (try? jpegData.write(to: fileURL)) != nil else { return }

        let entry = PhotoEntry(
            id: id,
            date: date,
            pose: pose,
            imagePath: filename,
            weightKg: nil
        )
        entries.append(entry)
        saveEntries()
    }

    func saveSession(images: [(UIImage, String)], date: String, weightKg: Double?) {
        for (image, pose) in images {
            let id = UUID()
            let filename = "\(date)_\(pose)_\(id.uuidString).jpg"
            let fileURL = photosDir.appendingPathComponent(filename)

            guard let jpegData = image.jpegData(compressionQuality: 0.8),
                  (try? jpegData.write(to: fileURL)) != nil else { continue }

            let entry = PhotoEntry(
                id: id,
                date: date,
                pose: pose,
                imagePath: filename,
                weightKg: weightKg
            )
            entries.append(entry)
        }
        saveEntries()
    }

    func deleteEntry(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let fileURL = photosDir.appendingPathComponent(entry.imagePath)
        try? FileManager.default.removeItem(at: fileURL)
        entries.removeAll { $0.id == id }
        saveEntries()
    }

    func reassignSessionDate(from oldDate: String, to newDate: String) {
        guard oldDate != newDate else { return }
        for i in entries.indices where entries[i].date == oldDate {
            let old = entries[i]
            // Rename file to reflect new date
            let newFilename = old.imagePath.replacingOccurrences(of: oldDate, with: newDate)
            let oldURL = photosDir.appendingPathComponent(old.imagePath)
            let newURL = photosDir.appendingPathComponent(newFilename)
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
            entries[i] = PhotoEntry(
                id: old.id, date: newDate, pose: old.pose,
                imagePath: newFilename, weightKg: old.weightKg
            )
        }
        saveEntries()
    }

    func deleteSession(date: String) {
        let toDelete = entries.filter { $0.date == date }
        for entry in toDelete {
            let fileURL = photosDir.appendingPathComponent(entry.imagePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        entries.removeAll { $0.date == date }
        saveEntries()
    }

    func entries(for date: String) -> [PhotoEntry] {
        entries.filter { $0.date == date }
    }

    var allDates: [String] {
        Array(Set(entries.map(\.date))).sorted(by: >)
    }

    func imageURL(for entry: PhotoEntry) -> URL {
        photosDir.appendingPathComponent(entry.imagePath)
    }

    func loadImage(for entry: PhotoEntry) -> UIImage? {
        let url = photosDir.appendingPathComponent(entry.imagePath)
        return loadDownsampled(url: url)
    }

    private func loadDownsampled(url: URL, maxDimension: CGFloat = 1200) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - HealthKit weight

    func latestWeight() async -> Double? {
        let weights = await PhoneHealthKitManager.shared.fetchBodyWeight(days: 1)
        return weights.last?.weightKg
    }
}
