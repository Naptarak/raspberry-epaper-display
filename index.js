const fetch = require('node-fetch');
const puppeteer = require('puppeteer');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const epaper = require('waveshare-epaper');

// Konfiguráció
const CONFIG = {
    updateInterval: 5 * 60 * 1000, // 5 perc
    display: {
        width: 640,
        height: 400,
        colors: 7
    }
};

// E-paper kijelző inicializálása
const display = new epaper.Epd4in01f();

async function initDisplay() {
    try {
        await display.init();
        console.log('E-paper kijelző inicializálva');
    } catch (error) {
        console.error('Hiba a kijelző inicializálásakor:', error);
        process.exit(1);
    }
}

async function captureWeatherPage() {
    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/chromium-browser',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    try {
        const page = await browser.newPage();
        await page.setViewport({
            width: CONFIG.display.width,
            height: CONFIG.display.height
        });
        
        // HTML fájl betöltése
        await page.goto(`file://${path.join(__dirname, 'weather.html')}`);
        
        // Várunk a tartalom betöltődésére
        await page.waitForSelector('.container', { timeout: 30000 });
        
        // Képernyőkép készítése
        const screenshot = await page.screenshot({
            type: 'png',
            fullPage: true
        });
        
        await browser.close();
        return screenshot;
        
    } catch (error) {
        console.error('Hiba a képernyőkép készítésekor:', error);
        await browser.close();
        throw error;
    }
}

async function processImageForEpaper(imageBuffer) {
    try {
        // Kép feldolgozása az e-paper kijelzőhöz
        const processedImage = await sharp(imageBuffer)
            .resize(CONFIG.display.width, CONFIG.display.height, {
                fit: 'contain',
                background: { r: 255, g: 255, b: 255 }
            })
            .raw()
            .toBuffer();
        
        return processedImage;
    } catch (error) {
        console.error('Hiba a kép feldolgozásakor:', error);
        throw error;
    }
}

async function updateDisplay() {
    try {
        console.log('Időjárás adatok frissítése...');
        
        // Képernyőkép készítése a weboldalról
        const screenshot = await captureWeatherPage();
        
        // Kép feldolgozása
        const processedImage = await processImageForEpaper(screenshot);
        
        // Kijelző frissítése
        await display.display(processedImage);
        
        console.log('Kijelző frissítve:', new Date().toLocaleString());
    } catch (error) {
        console.error('Hiba a kijelző frissítésekor:', error);
    }
}

// Fő program
async function main() {
    await initDisplay();
    
    // Első frissítés
    await updateDisplay();
    
    // Időzített frissítések
    setInterval(updateDisplay, CONFIG.updateInterval);
}

main().catch(console.error);