import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'analyzer.dart';
import 'migrator.dart';

class MigrationReportGenerator {
  final bool _verbose;

  MigrationReportGenerator({bool verbose = false}) : _verbose = verbose;

  Future<void> generateReport(
    MigrationAnalysisResult analysis,
    String outputPath, {
    bool jsonFormat = false,
  }) async {
    final file = File(outputPath);
    final content = jsonFormat
        ? _generateJsonReport(analysis)
        : _generateTextReport(analysis);
    await file.writeAsString(content);

    if (_verbose) {
      print('[INFO] Report written to $outputPath');
    }
  }

  String _generateJsonReport(MigrationAnalysisResult analysis) {
    return jsonEncode(analysis.toJson());
  }

  String _generateTextReport(MigrationAnalysisResult analysis) {
    final buffer = StringBuffer();

    buffer.writeln('Locus SDK Migration Report');
    buffer.writeln('═' * 60);
    buffer.writeln();
    buffer.writeln('Project: ${analysis.projectPath}');
    buffer.writeln('Generated: ${analysis.timestamp.toIso8601String()}');
    buffer.writeln();
    buffer.writeln('Summary');
    buffer.writeln('─' * 30);
    buffer.writeln('Total files analyzed: ${analysis.totalFiles}');
    buffer.writeln('Files with Locus SDK: ${analysis.filesWithLocus}');
    buffer.writeln('Total patterns found: ${analysis.totalMatches}');
    buffer.writeln();

    buffer.writeln('By Category:');
    for (final entry in analysis.matchesByCategory.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    if (analysis.matches.isNotEmpty) {
      buffer.writeln('Matched Patterns');
      buffer.writeln('─' * 30);

      for (final file in analysis.analyzedFiles.where((f) => f.hasLocusUsage)) {
        final fileMatches =
            analysis.matches.where((m) => m.filePath == file.path);

        if (fileMatches.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('${file.path}');
          buffer.writeln('  Line | Pattern | Change');

          for (final match in fileMatches) {
            buffer.writeln(
              '  ${match.line.toString().padLeft(4)} | ${match.patternId.padRight(30)} | '
              '${match.original.substring(0, min(20, match.original.length))} → '
              '${match.replacement.substring(0, min(20, match.replacement.length))}',
            );
          }
        }
      }
    }

    if (analysis.warnings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Warnings');
      buffer.writeln('─' * 30);

      for (final warning in analysis.warnings) {
        buffer.writeln('${warning.filePath}:${warning.line}');
        buffer.writeln('  Code: ${warning.code}');
        buffer.writeln('  Message: ${warning.message}');
        if (warning.suggestion != null) {
          buffer.writeln('  Suggestion: ${warning.suggestion}');
        }
        buffer.writeln();
      }
    }

    if (analysis.errors.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Errors');
      buffer.writeln('─' * 30);

      for (final error in analysis.errors) {
        buffer.writeln('${error.filePath}:${error.line}');
        buffer.writeln('  Code: ${error.code}');
        buffer.writeln('  Message: ${error.message}');
        buffer.writeln();
      }
    }

    buffer.writeln();
    buffer.writeln('═' * 60);
    buffer.writeln('End of Report');

    return buffer.toString();
  }

  String generateSummaryReport(MigrationResult result) {
    final buffer = StringBuffer();

    buffer.writeln();
    buffer.writeln('🚀 Locus SDK Migration Complete');
    buffer.writeln('═' * 60);

    if (result.dryRun) {
      buffer.writeln('⚠️  DRY RUN - No files were modified');
      buffer.writeln();
    }

    buffer.writeln('Summary');
    buffer.writeln('─' * 40);
    buffer.writeln('Files analyzed: ${result.analysis.totalFiles}');
    buffer.writeln('Files with Locus SDK: ${result.analysis.filesWithLocus}');
    buffer.writeln('Total patterns found: ${result.analysis.totalMatches}');
    buffer.writeln('Auto-migratable: ${result.analysis.autoMigratableCount}');
    buffer.writeln(
        'Manual review required: ${result.analysis.manualReviewCount}');
    buffer.writeln('Removed features: ${result.analysis.removedFeaturesCount}');
    buffer.writeln();

    if (result.backupPath != null) {
      buffer.writeln('📦 Backup created: ${result.backupPath}/backup.tar.gz');
      buffer.writeln();
    }

    buffer.writeln('Changes Applied');
    buffer.writeln('─' * 40);
    buffer.writeln('Files modified: ${result.filesModified}');
    buffer.writeln('Successful: ${result.successfulChanges}');
    buffer.writeln('Failed: ${result.failedChanges}');
    buffer.writeln();

    if (result.analysis.warnings.isNotEmpty) {
      buffer.writeln('⚠️  Warnings (${result.analysis.warnings.length})');
      for (final warning in result.analysis.warnings.take(5)) {
        buffer.writeln(
            '  - ${warning.filePath}:${warning.line} - ${warning.message}');
      }
      if (result.analysis.warnings.length > 5) {
        buffer.writeln('  ... and ${result.analysis.warnings.length - 5} more');
      }
      buffer.writeln();
    }

    if (result.analysis.errors.isNotEmpty) {
      buffer.writeln('❌ Errors (${result.analysis.errors.length})');
      for (final error in result.analysis.errors) {
        buffer
            .writeln('  - ${error.filePath}:${error.line} - ${error.message}');
      }
      buffer.writeln();
    }

    buffer.writeln('Next Steps');
    buffer.writeln('─' * 40);

    if (result.dryRun) {
      buffer.writeln('1. Review the changes above');
      buffer.writeln('2. Run `dart run locus:migrate` to apply changes');
    } else {
      if (result.analysis.manualReviewCount > 0) {
        buffer.writeln('1. Review files marked for manual review');
        buffer.writeln('2. Update any code that requires manual changes');
      }
      buffer.writeln('1. Run your tests to verify migration');
      buffer.writeln('2. Build your app to check for errors');
      if (result.backupPath != null) {
        buffer.writeln(
            '3. Backup is available at: ${result.backupPath}/backup.tar.gz');
        buffer.writeln(
            '   Run `tar -xzf ${result.backupPath}/backup.tar.gz` to restore');
      }
    }

    buffer.writeln();
    buffer.writeln('═' * 60);

    return buffer.toString();
  }

  String generateJsonSummary(MigrationResult result) {
    return jsonEncode(result.toJson());
  }
}
