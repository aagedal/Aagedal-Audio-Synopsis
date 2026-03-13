//
//  SidebarView.swift
//  MeetSum
//
//  Sidebar with meeting list and new meeting button
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var meetingStore: MeetingStore
    var processingMeetingIds: Set<UUID>
    var onNewMeeting: () -> Void
    var onImportAudio: () -> Void

    @State private var editingMeetingId: UUID?
    @State private var editingTitle: String = ""
    @State private var meetingToDelete: RecordingSession?
    @State private var searchText: String = ""

    private var filteredMeetings: [RecordingSession] {
        guard !searchText.isEmpty else { return meetingStore.meetings }
        let query = searchText.lowercased()
        return meetingStore.meetings.filter { meeting in
            meeting.title.lowercased().contains(query) ||
            meeting.transcription.lowercased().contains(query) ||
            meeting.notes.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // New Meeting / Import buttons
            HStack(spacing: 8) {
                Button(action: onNewMeeting) {
                    Label("New Meeting", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: onImportAudio) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Import audio file")
            }
            .padding()

            Divider()

            // Meeting list
            if meetingStore.meetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No meetings yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search meetings", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 4)

                if filteredMeetings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No matching meetings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $meetingStore.selectedMeetingId) {
                        ForEach(filteredMeetings, id: \.id) { meeting in
                            meetingRow(meeting)
                                .tag(meeting.id)
                                .contextMenu {
                                    Button("Rename") {
                                        editingMeetingId = meeting.id
                                        editingTitle = meeting.title
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        meetingToDelete = meeting
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .sheet(item: $editingMeetingId) { meetingId in
            renameSheet(meetingId: meetingId)
        }
        .alert("Delete Meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    meetingStore.deleteMeeting(meeting)
                    meetingToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete the meeting and its audio files.")
        }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: RecordingSession) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDate(meeting.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if meeting.duration > 0 {
                        Text(AudioUtils.formatDuration(meeting.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !meeting.transcription.isEmpty {
                    Text(meeting.transcription.prefix(60) + (meeting.transcription.count > 60 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if processingMeetingIds.contains(meeting.id) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func renameSheet(meetingId: UUID) -> some View {
        VStack(spacing: 16) {
            Text("Rename Meeting")
                .font(.headline)

            TextField("Title", text: $editingTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    editingMeetingId = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    meetingStore.renameMeeting(id: meetingId, newTitle: editingTitle)
                    editingMeetingId = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

// Make UUID conform to Identifiable for sheet(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
