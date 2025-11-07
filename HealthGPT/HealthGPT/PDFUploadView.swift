//
//  PDFUploadView.swift
//  HealthGPT
//
//  Created by Augustine Manadan on 8/4/25.
//
import SwiftUI

struct PDFUploadView: View {
    @State private var showPicker = false
    @State private var uploadedPDFURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Button("Upload PDF") {
                showPicker = true
            }
            .font(.headline)
            .padding()
            .background(Color.blue.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)

            if let uploaded = uploadedPDFURL {
                Text("Uploaded: \(uploaded.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .sheet(isPresented: $showPicker) {
            PDFPicker { url in
                uploadedPDFURL = url
                // TODO: Upload or process PDF file here
            }
        }
    }
}

#Preview {
    PDFUploadView()
}

