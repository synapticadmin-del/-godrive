import os
import sys
from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
BRAIN_DIR = r"C:\Users\kayf\.gemini\antigravity\brain\c52f7fd0-c7f9-4020-b6ab-a638160bcc69"

ICON_SRC = os.path.join(BRAIN_DIR, "tempo_app_icon_1785842471450.jpg")
HERO_RIDER_SRC = os.path.join(BRAIN_DIR, "tempo_hero_rider_1785842485164.jpg")
HERO_CAPTAIN_SRC = os.path.join(BRAIN_DIR, "tempo_hero_captain_1785842495509.jpg")

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print("Distributing AI generated Tempo assets across the project...")
    
    if not os.path.exists(ICON_SRC):
        print(f"Error: {ICON_SRC} not found")
        return
        
    icon_img = Image.open(ICON_SRC).convert("RGBA")
    hero_rider_img = Image.open(HERO_RIDER_SRC).convert("RGBA")
    hero_captain_img = Image.open(HERO_CAPTAIN_SRC).convert("RGBA")
    
    mipmaps = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    
    apps = ["rider", "captain"]
    
    # 1. Launcher Icons
    for app in apps:
        res_dir = os.path.join(REPO_ROOT, "apps", app, "android", "app", "src", "main", "res")
        for folder, sz in mipmaps.items():
            out_folder = os.path.join(res_dir, folder)
            os.makedirs(out_folder, exist_ok=True)
            icon_resized = icon_img.resize((sz, sz), Image.Resampling.LANCZOS)
            out_path = os.path.join(out_folder, "ic_launcher.png")
            icon_resized.save(out_path, "PNG")
            print(f"Saved icon {sz}x{sz} -> {out_path}")

    # 2. Asset Brand Images
    logo_512 = icon_img.resize((512, 512), Image.Resampling.LANCZOS)
    
    for app in apps:
        assets_dir = os.path.join(REPO_ROOT, "apps", app, "assets", "images")
        os.makedirs(assets_dir, exist_ok=True)
        
        logo_512.save(os.path.join(assets_dir, "tempo_logo.png"), "PNG")
        print(f"Saved brand assets for {app}")
        
    # Hero images
    rider_hero = hero_rider_img.resize((800, 450), Image.Resampling.LANCZOS)
    rider_hero.save(os.path.join(REPO_ROOT, "apps", "rider", "assets", "images", "login_hero_price.png"), "PNG")
    rider_hero.save(os.path.join(REPO_ROOT, "apps", "rider", "assets", "images", "login_hero_safety.png"), "PNG")
    
    captain_hero = hero_captain_img.resize((800, 450), Image.Resampling.LANCZOS)
    captain_hero.save(os.path.join(REPO_ROOT, "apps", "captain", "assets", "images", "login_hero_earn.png"), "PNG")
    captain_hero.save(os.path.join(REPO_ROOT, "apps", "captain", "assets", "images", "login_hero_safety.png"), "PNG")
    
    # Admin logo
    logo_512.save(os.path.join(REPO_ROOT, "apps", "admin", "public", "tempo-logo.png"), "PNG")
    
    print("All AI generated assets distributed successfully!")

if __name__ == "__main__":
    main()
