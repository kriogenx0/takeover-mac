//
//  Linker.swift
//  Takeover
//
//  Created by Alex Vaos on 2/27/25.
//

import Foundation

class Linker {
    static func linkOrMove(from: String, to: String) {
        // Link already exists. Recreate for now.
        // TODO: Check where the link points to.
        if isLink(path: from) {
            delete(path: from)
            link(from: from, to: to)
        } else {
            // Both folders exist.
            // For now, move FROM into TO.
            // TODO: Ask to merge.
            if !isLink(path: to) {
    //            link(from: from, to: to)
            }
        }
    }

    static func isLink(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return resourceValues.isSymbolicLink ?? false
        } catch {
            // Handle error, e.g., if the file doesn't exist or is inaccessible
            print("Error checking symbolic link at \(path): \(error)")
            return false
        }
    }

    static func delete(path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            print("Could not delete file at \(path): \(error)")
        }
    }

    static func link(from: String, to: String) {
//        shell("ln -s \(from) \(to)")
        let at = URL(fileURLWithPath: from)
        let withDestinationURL = URL(fileURLWithPath: to)
        do {
            try FileManager.default.createSymbolicLink(at: at, withDestinationURL: withDestinationURL)
        } catch {
            print("Error creating symlink")
        }
    }
    
    static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil
        task.launch()
        task.waitUntilExit()  // Wait for the command to complete

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        return String(data: data, encoding: .utf8) ?? ""
    }
}
