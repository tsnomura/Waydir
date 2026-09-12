import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/terminal/bulk_copy_command.dart';

void main() {
  group('bulkCopyToolFor', () {
    test('picks scp when sftp is involved, regardless of platform', () {
      expect(bulkCopyToolFor(involvesSftp: true), BulkCopyTool.scp);
    });

    test('picks the platform default otherwise', () {
      expect(
        bulkCopyToolFor(involvesSftp: false),
        Platform.isWindows ? BulkCopyTool.robocopy : BulkCopyTool.rsync,
      );
    });
  });

  group('buildBulkCopyCommand (robocopy)', () {
    test('a single folder appends its basename to the destination', () {
      if (!Platform.isWindows) return;

      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.robocopy,
        sources: [
          const BulkCopySource(path: r'X:\project\eo_06', isFolder: true),
        ],
        destinationDir: r'N:\backup',
        flags: ['/E', '/MT:8'],
      );
      expect(
        command,
        r'robocopy "X:\project\eo_06" "N:\backup\eo_06" /E /MT:8',
      );
    });

    test('quotes paths containing spaces', () {
      if (!Platform.isWindows) return;

      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.robocopy,
        sources: [
          const BulkCopySource(path: r'X:\My Project\eo 06', isFolder: true),
        ],
        destinationDir: r'N:\Back Up',
        flags: const [],
      );
      expect(command, r'robocopy "X:\My Project\eo 06" "N:\Back Up\eo 06"');
    });

    test('a single file copies via its parent dir with a name filter', () {
      if (!Platform.isWindows) return;

      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.robocopy,
        sources: [
          const BulkCopySource(path: r'X:\project\notes.txt', isFolder: false),
        ],
        destinationDir: r'N:\backup',
        flags: ['/Z'],
      );
      expect(command, r'robocopy "X:\project" "N:\backup" "notes.txt" /Z');
    });

    test('multiple folders become chained robocopy calls', () {
      if (!Platform.isWindows) return;

      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.robocopy,
        sources: [
          const BulkCopySource(path: r'X:\project\a', isFolder: true),
          const BulkCopySource(path: r'X:\project\b', isFolder: true),
        ],
        destinationDir: r'N:\backup',
        flags: ['/E'],
      );
      expect(
        command,
        r'robocopy "X:\project\a" "N:\backup\a" /E && '
        r'robocopy "X:\project\b" "N:\backup\b" /E',
      );
    });

    test(
      'multiple files sharing a parent directory are filtered in one call',
      () {
        if (!Platform.isWindows) return;

        final command = buildBulkCopyCommand(
          tool: BulkCopyTool.robocopy,
          sources: [
            const BulkCopySource(path: r'X:\project\a.txt', isFolder: false),
            const BulkCopySource(path: r'X:\project\b.txt', isFolder: false),
          ],
          destinationDir: r'N:\backup',
          flags: ['/Z'],
        );
        expect(
          command,
          r'robocopy "X:\project" "N:\backup" "a.txt" "b.txt" /Z',
        );
      },
    );

    test('a mix of folders and files groups files by parent directory, '
        'folders each getting their own call', () {
      if (!Platform.isWindows) return;

      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.robocopy,
        sources: [
          const BulkCopySource(path: r'X:\project\sub', isFolder: true),
          const BulkCopySource(path: r'X:\project\a.txt', isFolder: false),
          const BulkCopySource(path: r'X:\other\b.txt', isFolder: false),
        ],
        destinationDir: r'N:\backup',
        flags: const [],
      );
      expect(
        command,
        r'robocopy "X:\project\sub" "N:\backup\sub" && '
        r'robocopy "X:\project" "N:\backup" "a.txt" && '
        r'robocopy "X:\other" "N:\backup" "b.txt"',
      );
    });
  });

  group('buildBulkCopyCommand (rsync)', () {
    test('a single source passes through directly (no trailing slash) so '
        'rsync creates its own basename subfolder at the destination', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.rsync,
        sources: [
          const BulkCopySource(path: '/mnt/project/eo_06', isFolder: true),
        ],
        destinationDir: '/mnt/backup',
        flags: ['-a', '-z'],
      );
      expect(command, 'rsync -a -z /mnt/project/eo_06 /mnt/backup');
    });

    test('single-quotes paths containing spaces', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.rsync,
        sources: [
          const BulkCopySource(path: '/mnt/my project/eo 06', isFolder: true),
        ],
        destinationDir: '/mnt/back up',
        flags: const [],
      );
      expect(command, "rsync '/mnt/my project/eo 06' '/mnt/back up'");
    });

    test('multiple sources (mixed files and folders) are all listed before '
        'the single destination', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.rsync,
        sources: [
          const BulkCopySource(path: '/mnt/project/a', isFolder: true),
          const BulkCopySource(path: '/mnt/project/b.txt', isFolder: false),
        ],
        destinationDir: '/mnt/backup',
        flags: ['-a'],
      );
      expect(command, 'rsync -a /mnt/project/a /mnt/project/b.txt /mnt/backup');
    });
  });

  group('buildBulkCopyCommand (scp)', () {
    test('uploads a local source to an sftp destination', () {
      final localSource = Platform.isWindows
          ? r'C:\local\eo_06'
          : '/local/eo_06';
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.scp,
        sources: [BulkCopySource(path: localSource, isFolder: true)],
        destinationDir: 'sftp://user@example.com/remote/backup',
        flags: ['-r', '-C'],
      );
      final expectedSource = Platform.isWindows
          ? '"$localSource"'
          : localSource;
      final expectedDest = Platform.isWindows
          ? '"user@example.com:/remote/backup"'
          : 'user@example.com:/remote/backup';
      expect(command, 'scp -r -C $expectedSource $expectedDest');
    });

    test('downloads from an sftp source to a local destination', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.scp,
        sources: [
          const BulkCopySource(
            path: 'sftp://user@example.com/remote/eo_06',
            isFolder: true,
          ),
        ],
        destinationDir: Platform.isWindows
            ? r'C:\local\backup'
            : '/local/backup',
        flags: ['-r'],
      );
      final expectedSpec = Platform.isWindows
          ? '"user@example.com:/remote/eo_06"'
          : 'user@example.com:/remote/eo_06';
      final expectedDest = Platform.isWindows
          ? r'"C:\local\backup"'
          : '/local/backup';
      expect(command, 'scp -r $expectedSpec $expectedDest');
    });

    test('adds -P for a non-default port', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.scp,
        sources: [
          const BulkCopySource(
            path: 'sftp://user@example.com:2222/remote/eo_06',
            isFolder: true,
          ),
        ],
        destinationDir: Platform.isWindows
            ? r'C:\local\backup'
            : '/local/backup',
        flags: const [],
      );
      expect(command, contains('-P 2222'));
    });

    test('omits -P for the default ssh port (22)', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.scp,
        sources: [
          const BulkCopySource(
            path: 'sftp://user@example.com:22/remote/eo_06',
            isFolder: true,
          ),
        ],
        destinationDir: Platform.isWindows
            ? r'C:\local\backup'
            : '/local/backup',
        flags: const [],
      );
      expect(command, isNot(contains('-P')));
    });

    test('omits the username when the sftp URI has none', () {
      final command = buildBulkCopyCommand(
        tool: BulkCopyTool.scp,
        sources: [
          const BulkCopySource(
            path: 'sftp://example.com/remote/eo_06',
            isFolder: true,
          ),
        ],
        destinationDir: Platform.isWindows
            ? r'C:\local\backup'
            : '/local/backup',
        flags: const [],
      );
      expect(command, contains('example.com:/remote/eo_06'));
      expect(command, isNot(contains('@example.com:/remote/eo_06@')));
    });
  });
}
