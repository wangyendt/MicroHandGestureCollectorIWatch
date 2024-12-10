import subprocess
import os
import re

def capture_xcode_output(project_path=None, scheme_name=None):
    """
    捕获Xcode的输出日志
    
    Args:
        project_path: Xcode项目的路径 (.xcodeproj文件所在目录)
        scheme_name: 要运行的scheme名称
    
    Returns:
        输出日志文本
    """
    if not project_path:
        project_path = os.getcwd()
    
    # 构建xcodebuild命令
    cmd = ['xcodebuild']
    if scheme_name:
        cmd.extend(['-scheme', scheme_name])
    
    try:
        # 运行xcodebuild并捕获输出
        process = subprocess.Popen(
            cmd,
            cwd=project_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )
        
        stdout, stderr = process.communicate()
        
        # 合并标准输出和错误输出
        output = stdout + stderr
        
        # 清理ANSI转义序列
        clean_output = re.sub(r'\x1b\[[0-9;]*m', '', output)
        
        return clean_output
        
    except subprocess.CalledProcessError as e:
        print(f"执行xcodebuild时发生错误: {e}")
        return None
    except Exception as e:
        print(f"发生未知错误: {e}")
        return None

def save_output_to_file(output, filename="xcode_output.log"):
    """
    将输出保存到文件
    
    Args:
        output: 要保存的文本
        filename: 输出文件名
    """
    try:
        with open(filename, 'w') as f:
            f.write(output)
        print(f"输出已保存到: {filename}")
    except Exception as e:
        print(f"保存文件时发生错误: {e}")

# 使用示例
if __name__ == "__main__":
    # 获取当前目录下Xcode项目的输出
    output = capture_xcode_output()
    if output:
        print("Xcode输出:")
        print(output)
        
        # 保存到文件
        save_output_to_file(output)