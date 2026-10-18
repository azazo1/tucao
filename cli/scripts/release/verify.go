package main

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// 各平台可执行文件头的固定取值.
const (
	elfMagic       = "\x7fELF"
	machoMagicLE   = 0xfeedfacf
	machoMagicBE   = 0xcffaedfe
	machoTypeAMD64 = 0x01000007
	machoTypeARM64 = 0x0100000c
	peMachineAMD64 = 0x8664
	peMachineARM64 = 0xaa64
)

// allTargets 返回全部发布目标, 顺序固定, 便于日志与产物清单稳定.
func allTargets() []target {
	specs := [][2]string{
		{"linux", "amd64"},
		{"linux", "arm64"},
		{"darwin", "amd64"},
		{"darwin", "arm64"},
		{"windows", "amd64"},
		{"windows", "arm64"},
	}
	targets := make([]target, 0, len(specs))
	for _, spec := range specs {
		resolved, err := resolveTarget(spec[0], spec[1])
		if err != nil {
			// 目标表是硬编码的, 出错说明常量写错了.
			panic(err)
		}
		targets = append(targets, resolved)
	}
	return targets
}

// verifyArtifacts 校验 dist 目录里的全部产物.
//
// 交叉编译不会运行产物, 所以这里查三件事: 归档里只有一个预期的可执行文件,
// 文件头与目标平台一致, 以及二进制里确实带着本次构建的版本号.
func verifyArtifacts(release, display string) error {
	var problems []string
	for _, resolved := range allTargets() {
		build := metadataFor(resolved, display, release, true)
		if err := verifyArchive(build, resolved); err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", filepath.Base(build.ArchivePath), err))
			continue
		}
		fmt.Printf("校验通过: %s\n", filepath.Base(build.ArchivePath))
	}
	if len(problems) > 0 {
		return fmt.Errorf("产物校验失败:\n  %s", joinLines(problems))
	}
	return nil
}

// verifyArchive 打开一个归档, 校验其中的可执行文件.
func verifyArchive(build metadata, resolved target) error {
	binaryName := filepath.Base(build.BinaryPath)
	payload, err := readArchiveEntry(build.ArchivePath, binaryName)
	if err != nil {
		return err
	}
	if err := checkExecutable(payload, resolved); err != nil {
		return err
	}
	// 版本号是编译期注入的字符串, 直接找字节就能确认注入成功.
	if !bytes.Contains(payload, []byte(build.BuildVersion)) {
		return fmt.Errorf("二进制里没有版本号 %q", build.BuildVersion)
	}
	return nil
}

// readArchiveEntry 取出归档里的唯一文件内容.
func readArchiveEntry(archivePath, entryName string) ([]byte, error) {
	file, err := os.Open(archivePath)
	if err != nil {
		return nil, fmt.Errorf("打开归档失败: %w", err)
	}
	defer file.Close()

	if filepath.Ext(archivePath) == ".zip" {
		return readZipEntry(archivePath, entryName)
	}
	compressor, err := gzip.NewReader(file)
	if err != nil {
		return nil, fmt.Errorf("解压失败: %w", err)
	}
	defer compressor.Close()
	reader := tar.NewReader(compressor)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("归档里没有 %s", entryName)
		}
		if err != nil {
			return nil, fmt.Errorf("读取归档失败: %w", err)
		}
		if header.Name != entryName {
			return nil, fmt.Errorf("归档里有意外的条目 %s", header.Name)
		}
		return io.ReadAll(reader)
	}
}

// readZipEntry 取出 zip 里的唯一文件内容.
func readZipEntry(archivePath, entryName string) ([]byte, error) {
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, fmt.Errorf("打开归档失败: %w", err)
	}
	defer reader.Close()
	if len(reader.File) != 1 {
		return nil, fmt.Errorf("归档里应只有一个条目, 实际 %d 个", len(reader.File))
	}
	entry := reader.File[0]
	if entry.Name != entryName {
		return nil, fmt.Errorf("归档条目为 %s, 期望 %s", entry.Name, entryName)
	}
	opened, err := entry.Open()
	if err != nil {
		return nil, fmt.Errorf("读取条目失败: %w", err)
	}
	defer opened.Close()
	return io.ReadAll(opened)
}

// checkExecutable 按文件头校验可执行文件的平台与架构.
func checkExecutable(payload []byte, resolved target) error {
	if len(payload) < 64 {
		return fmt.Errorf("文件太短, 只有 %d 字节", len(payload))
	}
	switch resolved.GOOS {
	case "linux":
		return checkELF(payload, resolved.GOARCH)
	case "darwin":
		return checkMachO(payload, resolved.GOARCH)
	case "windows":
		return checkPE(payload, resolved.GOARCH)
	default:
		return fmt.Errorf("未知目标系统: %s", resolved.GOOS)
	}
}

func checkELF(payload []byte, goarch string) error {
	if string(payload[:4]) != elfMagic {
		return errors.New("不是 ELF 文件")
	}
	// e_machine 在文件头偏移 18, 2 字节小端.
	machine := binary.LittleEndian.Uint16(payload[18:20])
	want := map[string]uint16{"amd64": 62, "arm64": 183}[goarch]
	if machine != want {
		return fmt.Errorf("ELF 架构为 %d, 期望 %d", machine, want)
	}
	return nil
}

func checkMachO(payload []byte, goarch string) error {
	magic := binary.LittleEndian.Uint32(payload[0:4])
	if magic != machoMagicLE && magic != machoMagicBE {
		return errors.New("不是 Mach-O 文件")
	}
	// cputype 在偏移 4, 按文件头魔数决定字节序.
	var cputype uint32
	if magic == machoMagicLE {
		cputype = binary.LittleEndian.Uint32(payload[4:8])
	} else {
		cputype = binary.BigEndian.Uint32(payload[4:8])
	}
	want := map[string]uint32{"amd64": machoTypeAMD64, "arm64": machoTypeARM64}[goarch]
	if cputype != want {
		return fmt.Errorf("Mach-O 架构为 %#x, 期望 %#x", cputype, want)
	}
	return nil
}

func checkPE(payload []byte, goarch string) error {
	if payload[0] != 'M' || payload[1] != 'Z' {
		return errors.New("不是 PE 文件")
	}
	offset := binary.LittleEndian.Uint32(payload[0x3c:0x40])
	if int(offset)+6 > len(payload) {
		return errors.New("PE 头偏移越界")
	}
	if string(payload[offset:offset+4]) != "PE\x00\x00" {
		return errors.New("PE 签名不正确")
	}
	machine := binary.LittleEndian.Uint16(payload[offset+4 : offset+6])
	want := map[string]uint16{"amd64": peMachineAMD64, "arm64": peMachineARM64}[goarch]
	if machine != want {
		return fmt.Errorf("PE 架构为 %#x, 期望 %#x", machine, want)
	}
	return nil
}

// joinLines 把多行问题拼成一段, 缩进后便于阅读.
func joinLines(lines []string) string {
	buffer := &bytes.Buffer{}
	for index, line := range lines {
		if index > 0 {
			buffer.WriteString("\n  ")
		}
		buffer.WriteString(line)
	}
	return buffer.String()
}
