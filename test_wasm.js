const puppeteer = require('puppeteer');
const express = require('express');
const path = require('path');

const app = express();

app.use((req, res, next) => {
    console.log('[SERVER REQUEST]', req.method, req.url);
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    next();
});

app.use(express.static(path.join(__dirname, 'build-wasm/bin')));

const server = app.listen(8000, async () => {
    console.log('Server started on port 8000');
    
    const browser = await puppeteer.launch({
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--use-gl=angle', // Or '--use-gl=swiftshader' to ensure software WebGL if needed
        ]
    });
    const page = await browser.newPage();
    
    page.on('console', msg => {
        console.log(`[BROWSER CONSOLE] ${msg.type().toUpperCase()}: ${msg.text()}`);
    });
    page.on('pageerror', err => {
        console.log(`[BROWSER ERROR] ${err.toString()}`);
    });
    page.on('requestfailed', request => {
        console.log(`[REQUEST FAILED] ${request.url()} - ${request.failure().errorText}`);
    });

    try {
        await page.goto('http://localhost:8000/luanti.html', { waitUntil: 'networkidle2', timeout: 30000 });
        console.log('Page loaded. Clicking to start engine...');
        
        // Emscripten's default HTML has a canvas. Sometimes there is a start button.
        // Wait a bit then click the center of the page.
        await new Promise(resolve => setTimeout(resolve, 2000));
        await page.mouse.click(400, 300); // Click somewhere in the middle to trigger start

        console.log('Waiting for engine to initialize and log errors...');
        await new Promise(resolve => setTimeout(resolve, 20000)); // wait 20s
    } catch (e) {
        console.error('Error navigating:', e);
    } finally {
        await browser.close();
        server.close();
    }
});
