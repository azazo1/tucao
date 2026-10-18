// Command release 负责 CLI 的版本解析, 构建与打包.
//
// 供 just 配方与 CI 使用, 保持与安卓端一致的产物命名习惯:
// 版本号来自 git tag (统一版本号), 归档名形如
// tucao-cli-<版本>-<平台>-<架构>.tar.gz 或 .zip.
package main

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

const (
	projectName   = "tucao-cli"
	mainPackage   = "./cmd/tucao"
	versionSymbol = "github.com/azazo1/tucao/cli/internal/cli.Version"
	binaryDir     = "bin"
	distDirectory = "dist"
)

var (
	semverPattern  = regexp.MustCompile(`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`)
	versionPattern = regexp.MustCompile(`^[0-9A-Za-z][0-9A-Za-z.+-]*$`)
	dirNamePattern = regexp.MustCompile(`^[A-Za-z0-9_]+$`)
)

// versionTagMatch 是版本 tag 的匹配模式, 与安卓端构建版本脚本的 TAG_PREFIX 保持一致.
const versionTagMatch = "v[0-9]*"

// target 是一次构建的目标平台.
type target struct {
	GOOS     string
	GOARCH   string
	Platform string
	Arch     string
}

// metadata 是构建产物的路径与版本信息.
type metadata struct {
	BuildVersion string
	ArchiveName  string
	BinaryPath   string
	ArchivePath  string
}

func main() {
	mode := flag.String("mode", "build", "执行模式: metadata, build 或 dist")
	targetOS := flag.String("target-os", runtime.GOOS, "目标系统")
	targetArch := flag.String("target-arch", runtime.GOARCH, "目标架构")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	resolved, err := resolveTarget(*targetOS, *targetArch)
	if err != nil {
		logger.Error("解析构建目标失败", "error", err)
		os.Exit(1)
	}
	build, err := resolveMetadata(resolved)
	if err != nil {
		logger.Error("解析构建版本失败", "error", err)
		os.Exit(1)
	}

	switch *mode {
	case "metadata":
		fmt.Printf("build_version=%s\n", build.BuildVersion)
		fmt.Printf("binary_path=%s\n", build.BinaryPath)
		fmt.Printf("archive_path=%s\n", build.ArchivePath)
	case "build":
		if err := buildBinary(build, resolved, logger); err != nil {
			logger.Error("构建 CLI 失败", "error", err)
			os.Exit(1)
		}
	case "dist":
		if err := buildBinary(build, resolved, logger); err != nil {
			logger.Error("构建 CLI 失败", "error", err)
			os.Exit(1)
		}
		if err := createArchive(build, resolved, logger); err != nil {
			logger.Error("打包失败", "error", err)
			os.Exit(1)
		}
	default:
		logger.Error("未知模式", "mode", *mode)
		os.Exit(2)
	}
}

func resolveTarget(goos, goarch string) (target, error) {
	platforms := map[string]string{"linux": "linux", "darwin": "macos", "windows": "windows"}
	architectures := map[string]string{"amd64": "x86_64", "arm64": "aarch64"}
	platform, ok := platforms[goos]
	if !ok {
		return target{}, fmt.Errorf("不支持的目标系统: %s", goos)
	}
	arch, ok := architectures[goarch]
	if !ok {
		return target{}, fmt.Errorf("不支持的目标架构: %s", goarch)
	}
	if !dirNamePattern.MatchString(platform) || !dirNamePattern.MatchString(arch) {
		return target{}, errors.New("目标名称含非法字符")
	}
	return target{GOOS: goos, GOARCH: goarch, Platform: platform, Arch: arch}, nil
}

func resolveMetadata(resolved target) (metadata, error) {
	version := strings.TrimSpace(os.Getenv("TUCAO_BUILD_VERSION"))
	release := strings.TrimSpace(os.Getenv("TUCAO_RELEASE_VERSION"))
	if version == "" || release == "" {
		tag, describeVersion, err := gitVersion()
		if err != nil {
			return metadata{}, err
		}
		if version == "" {
			version = tag
		}
		if release == "" {
			release = describeVersion
		}
	}
	if !versionPattern.MatchString(release) {
		return metadata{}, fmt.Errorf("版本号含非法字符: %s", release)
	}
	binaryName := "tucao"
	if resolved.GOOS == "windows" {
		binaryName += ".exe"
	}
	archiveExtension := ".tar.gz"
	if resolved.GOOS == "windows" {
		archiveExtension = ".zip"
	}
	archiveName := fmt.Sprintf("%s-%s-%s-%s%s", projectName, release, resolved.Platform, resolved.Arch, archiveExtension)
	return metadata{
		BuildVersion: version,
		ArchiveName:  archiveName,
		BinaryPath:   filepath.Join(binaryDir, binaryName),
		ArchivePath:  filepath.Join(distDirectory, archiveName),
	}, nil
}

// gitVersion 取最近版本 tag 与按 tag 推导的版本.
func gitVersion() (tag string, describe string, err error) {
	return gitVersionIn("")
}

// gitVersionIn 在指定目录里解析版本, 目录为空时用当前目录.
//
// 必须带 --match: 预发布用的滚动 tag (dev-latest) 也指向分支上的提交,
// 不加过滤就会被 describe 挑成"最近的 tag", 于是版本号变成 dev-latest 直接失败.
// 它的名字不带版本前缀, 同时又是轻量 tag, 这里再加一层前缀过滤双保险.
func gitVersionIn(dir string) (tag string, describe string, err error) {
	tagBytes, err := gitDescribe(dir, "--tags", "--abbrev=0", "--match", versionTagMatch)
	if err != nil {
		// 没有任何版本 tag 时用 devel 作为基础版本.
		return "devel", "devel", nil
	}
	tag = strings.TrimSpace(string(tagBytes))
	if !semverPattern.MatchString(tag) {
		return "", "", fmt.Errorf("最近的版本 tag 不是 vX.Y.Z 形式: %s", tag)
	}
	// 不带 --long: HEAD 正好在版本 tag 上时只输出 tag, 与安卓端的版本规则一致.
	describeBytes, err := gitDescribe(dir, "--tags", "--always", "--dirty", "--match", versionTagMatch)
	describe = tag
	if err == nil {
		describe = strings.TrimSpace(string(describeBytes))
	}
	describe = sanitizeVersion(describe)
	return tag, describe, nil
}

// gitDescribe 执行 git describe.
func gitDescribe(dir string, args ...string) ([]byte, error) {
	command := exec.Command("git", append([]string{"describe"}, args...)...)
	command.Dir = dir
	return command.Output()
}

// sanitizeVersion 把 git describe 的输出整理成合法的版本字符串.
func sanitizeVersion(raw string) string {
	text := strings.TrimSpace(raw)
	text = strings.ReplaceAll(text, " ", ".")
	text = strings.ReplaceAll(text, "~", ".")
	if text == "" {
		return "devel"
	}
	var builder strings.Builder
	for _, symbol := range text {
		switch {
		case symbol >= '0' && symbol <= '9':
			builder.WriteRune(symbol)
		case symbol >= 'a' && symbol <= 'z':
			builder.WriteRune(symbol)
		case symbol >= 'A' && symbol <= 'Z':
			builder.WriteRune(symbol)
		case symbol == '.' || symbol == '-' || symbol == '+':
			builder.WriteRune(symbol)
		default:
			builder.WriteRune('.')
		}
	}
	result := strings.Trim(builder.String(), ".-+")
	if result == "" {
		return "devel"
	}
	return result
}

func buildBinary(build metadata, resolved target, logger *slog.Logger) error {
	if err := os.MkdirAll(binaryDir, 0o755); err != nil {
		return fmt.Errorf("创建输出目录失败: %w", err)
	}
	logger.Info("构建 CLI", "version", build.BuildVersion, "target", resolved.GOOS+"/"+resolved.GOARCH)
	command := exec.Command("go", "build",
		"-trimpath",
		"-ldflags", fmt.Sprintf("-s -w -X %s=%s", versionSymbol, build.BuildVersion),
		"-o", build.BinaryPath,
		mainPackage,
	)
	command.Env = append(os.Environ(), "GOOS="+resolved.GOOS, "GOARCH="+resolved.GOARCH, "CGO_ENABLED=0")
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("go build 失败: %w", err)
	}
	return nil
}

func createArchive(build metadata, resolved target, logger *slog.Logger) error {
	if err := os.MkdirAll(distDirectory, 0o755); err != nil {
		return fmt.Errorf("创建归档目录失败: %w", err)
	}
	binaryName := filepath.Base(build.BinaryPath)
	if resolved.GOOS == "windows" {
		if err := createZip(build.ArchivePath, build.BinaryPath, binaryName); err != nil {
			return err
		}
	} else {
		if err := createTarGz(build.ArchivePath, build.BinaryPath, binaryName); err != nil {
			return err
		}
	}
	logger.Info("已生成发布归档", "archive", build.ArchivePath)
	return nil
}

func createTarGz(archivePath, binaryPath, binaryName string) error {
	file, err := os.Create(archivePath)
	if err != nil {
		return fmt.Errorf("创建归档失败: %w", err)
	}
	defer file.Close()
	compressor := gzip.NewWriter(file)
	writer := tar.NewWriter(compressor)
	source, err := os.Open(binaryPath)
	if err != nil {
		return fmt.Errorf("读取二进制失败: %w", err)
	}
	defer source.Close()
	info, err := source.Stat()
	if err != nil {
		return fmt.Errorf("读取文件信息失败: %w", err)
	}
	header := &tar.Header{
		Name:    binaryName,
		Mode:    0o755,
		Size:    info.Size(),
		ModTime: info.ModTime(),
	}
	if err := writer.WriteHeader(header); err != nil {
		return fmt.Errorf("写入归档头失败: %w", err)
	}
	if _, err := io.Copy(writer, source); err != nil {
		return fmt.Errorf("写入归档失败: %w", err)
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("关闭归档失败: %w", err)
	}
	if err := compressor.Close(); err != nil {
		return fmt.Errorf("关闭压缩失败: %w", err)
	}
	return nil
}

func createZip(archivePath, binaryPath, binaryName string) error {
	file, err := os.Create(archivePath)
	if err != nil {
		return fmt.Errorf("创建归档失败: %w", err)
	}
	defer file.Close()
	writer := zip.NewWriter(file)
	entry, err := writer.Create(binaryName)
	if err != nil {
		return fmt.Errorf("创建归档条目失败: %w", err)
	}
	source, err := os.Open(binaryPath)
	if err != nil {
		return fmt.Errorf("读取二进制失败: %w", err)
	}
	defer source.Close()
	if _, err := io.Copy(entry, source); err != nil {
		return fmt.Errorf("写入归档失败: %w", err)
	}
	if err := writer.Close(); err != nil {
		return fmt.Errorf("关闭归档失败: %w", err)
	}
	return nil
}
