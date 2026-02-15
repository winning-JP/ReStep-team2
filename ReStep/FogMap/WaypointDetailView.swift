import SwiftUI
import CoreLocation
import PhotosUI

actor PlaceNameResolver {
    static let shared = PlaceNameResolver()
    private var cache: [String: String] = [:]

    func resolveName(latitude: Double, longitude: Double) async -> String? {
        let key = String(format: "%.5f,%.5f", latitude, longitude)
        if let cached = cache[key] {
            return cached
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let name = Self.format(placemark: placemark)
            if let name, !name.isEmpty {
                cache[key] = name
            }
            return name
        } catch {
            return nil
        }
    }

    private static func format(placemark: CLPlacemark) -> String? {
        let candidates = [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if candidates.isEmpty { return nil }
        return candidates.joined(separator: " ")
    }
}

// MARK: - ウェイポイント追加ビュー

struct WaypointDetailView: View {
    let coordinate: CLLocationCoordinate2D
    let onSave: (String, String, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: Image?
    @State private var photoData: Data?

    var body: some View {
        NavigationView {
            Form {
                Section("場所情報") {
                    HStack {
                        Text("緯度")
                        Spacer()
                        Text(String(format: "%.6f", coordinate.latitude))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("経度")
                        Spacer()
                        Text(String(format: "%.6f", coordinate.longitude))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("ウェイポイント情報") {
                    TextField("タイトル", text: $title)
                    TextField("メモ", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("写真") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if let photoImage {
                            photoImage
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label("写真を選択", systemImage: "photo.badge.plus")
                        }
                    }
                    .onChange(of: selectedPhoto) {
                        Task { await loadPhoto() }
                    }

                    if photoImage != nil {
                        Button("写真を削除", role: .destructive) {
                            selectedPhoto = nil
                            photoImage = nil
                            photoData = nil
                        }
                    }
                }
            }
            .navigationTitle("ウェイポイント追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(title.isEmpty ? "ウェイポイント" : title, note, photoData)
                        dismiss()
                    }
                }
            }
        }
    }

    private func loadPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        photoImage = Image(uiImage: uiImage)
        // JPEG圧縮して保存
        photoData = uiImage.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - ウェイポイント詳細表示ビュー

struct WaypointInfoView: View {
    let waypoint: Waypoint
    let onDelete: () -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var loadedImage: Image?
    @State private var placeName: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // タイトル
                    Text(waypoint.title.isEmpty ? "ウェイポイント" : waypoint.title)
                        .font(.title2.bold())

                    // 場所情報
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.purple)
                        Text(String(format: "%.6f, %.6f", waypoint.latitude, waypoint.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let placeName, !placeName.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "location")
                                .foregroundStyle(.secondary)
                            Text(placeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 日時
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(formatDate(waypoint.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // メモ
                    if !waypoint.note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("メモ")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Text(waypoint.note)
                                .font(.body)
                        }
                    } else {
                        Text("メモなし")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // 写真（S3 URL）
                    if waypoint.photoUrl != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("写真")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            if let loadedImage {
                                loadedImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 200)
                                    .overlay {
                                        ProgressView()
                                    }
                            }
                        }
                    }

                    Spacer()

                    // 編集ボタン
                    Button {
                        onEdit()
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("ウェイポイントを編集")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    // 削除ボタン
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("ウェイポイントを削除")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("ウェイポイント詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("ウェイポイントを削除", isPresented: $showDeleteConfirm) {
                Button("削除", role: .destructive) {
                    onDelete()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("このウェイポイントを削除しますか？この操作は取り消せません。")
            }
            .task {
                await loadPhoto()
                await loadPlaceName()
            }
        }
    }

    private func loadPhoto() async {
        // S3 URLから読み込み
        if let urlString = waypoint.photoUrl, let url = URL(string: urlString) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    loadedImage = Image(uiImage: uiImage)
                }
            } catch {
                DebugLog.log("WaypointInfoView.loadPhoto error: \(error.localizedDescription)")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func loadPlaceName() async {
        placeName = await PlaceNameResolver.shared.resolveName(latitude: waypoint.latitude, longitude: waypoint.longitude)
    }
}

// MARK: - ウェイポイント編集ビュー

struct WaypointEditView: View {
    let waypoint: Waypoint
    let onSave: (String, String, Data?, Bool) -> Void  // title, note, newPhotoData, removePhoto

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: Image?
    @State private var newPhotoData: Data?
    @State private var hasExistingPhoto: Bool
    @State private var removePhoto = false

    init(waypoint: Waypoint, onSave: @escaping (String, String, Data?, Bool) -> Void) {
        self.waypoint = waypoint
        self.onSave = onSave
        _title = State(initialValue: waypoint.title)
        _note = State(initialValue: waypoint.note)
        _hasExistingPhoto = State(initialValue: waypoint.photoUrl != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("場所情報") {
                    HStack {
                        Text("緯度")
                        Spacer()
                        Text(String(format: "%.6f", waypoint.latitude))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("経度")
                        Spacer()
                        Text(String(format: "%.6f", waypoint.longitude))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("ウェイポイント情報") {
                    TextField("タイトル", text: $title)
                    TextField("メモ", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("写真") {
                    if let photoImage {
                        photoImage
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if hasExistingPhoto && !removePhoto {
                        if let urlString = waypoint.photoUrl, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .failure:
                                    Label("読み込みエラー", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.secondary)
                                default:
                                    ProgressView()
                                        .frame(height: 100)
                                }
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            hasExistingPhoto || photoImage != nil ? "写真を変更" : "写真を選択",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .onChange(of: selectedPhoto) {
                        Task { await loadNewPhoto() }
                    }

                    if photoImage != nil || (hasExistingPhoto && !removePhoto) {
                        Button("写真を削除", role: .destructive) {
                            selectedPhoto = nil
                            photoImage = nil
                            newPhotoData = nil
                            removePhoto = true
                        }
                    }
                }
            }
            .navigationTitle("ウェイポイント編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            title.isEmpty ? "ウェイポイント" : title,
                            note,
                            newPhotoData,
                            removePhoto
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private func loadNewPhoto() async {
        guard let item = selectedPhoto,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        photoImage = Image(uiImage: uiImage)
        newPhotoData = uiImage.jpegData(compressionQuality: 0.8)
        removePhoto = false
    }
}
