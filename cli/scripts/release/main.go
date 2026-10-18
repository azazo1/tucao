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
	semverPattern = regexp.MustCompile(`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`)
	// 版本里允许 ^: 工作区有改动时, 规则用 ^ 连接短 hash (与安卓端口径一致).
	versionPattern = regexp.MustCompile(`^[0-9A-Za-z][0-9A-Za-z.+-]*\^?[0-9A-Za-z]*$`)
	dirNamePattern = regexp.MustCompile(`^[A-Za-z0-9_]+$`)
)

// versionTagPrefix 是版本 tag 的前缀, 与安卓端构建版本脚本的 TAG_PREFIX 保持一致.
const versionTagPrefix = "v"

// versionTagMatch 是版本 tag 的匹配模式, 用于过滤掉预发布之类不带前缀的 tag.
const versionTagMatch = versionTagPrefix + "[0-9]*"

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
	display := strings.TrimSpace(os.Getenv("TUCAO_BUILD_VERSION"))
	release := strings.TrimSpace(os.Getenv("TUCAO_RELEASE_VERSION"))
	if display == "" || release == "" {
		info, err := gitVersion()
		if err != nil {
			return metadata{}, err
		}
		if display == "" {
			display = info.Display
		}
		if release == "" {
			release = info.Release
		}
	}
	// 产物名统一不带 tag 前缀, 传进来的值带 v 时剥掉, 免得产出 tucao-cli-v1.3.0-....
	release = strings.TrimPrefix(release, versionTagPrefix)
	if !versionPattern.MatchString(release) {
		return metadata{}, fmt.Errorf("版本号含非法字符: %s", release)
	}
	if display == "" {
		display = versionTagPrefix + release
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
		BuildVersion: display,
		ArchiveName:  archiveName,
		BinaryPath:   filepath.Join(binaryDir, binaryName),
		ArchivePath:  filepath.Join(distDirectory, archiveName),
	}, nil
}

// versionInfo 是同一次构建里的两个版本号.
//
// 两者样式不同是刻意的, 与安卓端的构建版本脚本保持一致:
// 二进制里显示的版本跟随 tag 样式 (带前缀), 产物名里用剥掉前缀的那个.
type versionInfo struct {
	// Display 注入二进制, 例如 v1.3.0 或 v1.3.0-1e63ec9.
	Display string
	// Release 进产物名, 例如 1.3.0 或 1.3.0-1e63ec9.
	Release string
}

// gitVersion 按当前仓库计算版本.
func gitVersion() (versionInfo, error) {
	return gitVersionIn("")
}

// gitVersionIn 在指定目录里计算版本, 目录为空时用当前目录.
//
// 规则与安卓端的 scripts/build-version.py 一致:
// HEAD 正好在版本 tag 上时只给 tag, 否则追加 - 与 7 位短 hash,
// 工作区有未提交改动时改用 ^ 分隔. 仓库里没有版本 tag 时回落到 devel.
//
// 找 tag 必须带前缀过滤: 预发布用的滚动 tag (dev-latest) 也指向分支上的提交,
// 不过滤就会被当成版本号.
func gitVersionIn(dir string) (versionInfo, error) {
	tag := exactVersionTag(dir)
	if tag == "" {
		latest, err := gitOutput(dir, "describe", "--tags", "--abbrev=0", "--match", versionTagMatch)
		if err == nil {
			candidate := strings.TrimSpace(latest)
			if semverPattern.MatchString(candidate) {
				tag = candidate
			}
		}
	}
	if tag == "" {
		// 没有任何版本 tag 时没有可用的基础版本.
		return versionInfo{Display: "devel", Release: "devel"}, nil
	}

	commit, err := gitOutput(dir, "rev-parse", "--short=7", "HEAD")
	if err != nil {
		return versionInfo{}, fmt.Errorf("读取当前提交失败: %w", err)
	}
	shortHash := strings.TrimSpace(commit)

	display := tag
	switch {
	case gitDirty(dir):
		display = tag + "^" + shortHash
	case tag != exactVersionTag(dir):
		// 不在 tag 上时才追加短 hash.
		display = tag + "-" + shortHash
	}
	return versionInfo{
		Display: display,
		Release: strings.TrimPrefix(display, versionTagPrefix),
	}, nil
}

// exactVersionTag 返回当前 HEAD 上的版本 tag, 没有时返回空.
func exactVersionTag(dir string) string {
	output, err := gitOutput(dir, "tag", "--points-at", "HEAD")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(output, "\n") {
		candidate := strings.TrimSpace(line)
		if candidate != "" && semverPattern.MatchString(candidate) {
			return candidate
		}
	}
	return ""
}

// gitDirty 判断工作区是否有未提交的改动.
func gitDirty(dir string) bool {
	command := exec.Command("git", "diff-index", "--quiet", "HEAD", "--")
	command.Dir = dir
	err := command.Run()
	if err == nil {
		return false
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		// diff-index 用退出码 1 表示有差异.
		return exitErr.ExitCode() == 1
	}
	return false
}

// gitOutput 执行 git 命令并返回标准输出.
func gitOutput(dir string, args ...string) (string, error) {
	command := exec.Command("git", args...)
	command.Dir = dir
	output, err := command.Output()
	return string(output), err
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
