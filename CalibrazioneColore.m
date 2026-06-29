%% Script di Calibrazione Colore HSV Avanzato - ESP32-CAM
% Supporta il rilevamento del Nero e campionamento tramite Click
%
% AUTORE: Gemini AI
% DATA: 12-03-2026

clear; clc; close all;

%% ========== CONFIGURAZIONE ==========
ipAddress = 'http://192.168.178.150';
fprintf('CALIBRAZIONE COLORE HSV AVANZATA\n');
fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n');

%% ========== ACQUISIZIONE IMMAGINE ==========
fprintf('Acquisizione immagine da ESP32-CAM...\n');
try
    img = imread([ipAddress, '/jpg']);
    img = imrotate(img, 180); % Ruota se la cam è montata sottosopra
    fprintf('Immagine acquisita: %dx%d pixel\n\n', size(img, 2), size(img, 1));
catch
    error('Connessione fallita. Verifica l''IP del robot.');
end

%% ========== INTERFACCIA CALIBRAZIONE ==========
hFig = figure('Name', 'Calibrazione Avanzata HSV (Clicca l''immagine per campionare)', ...
              'NumberTitle', 'off', ...
              'Position', [50, 50, 1200, 850]);

imgHSV = rgb2hsv(img);

% --- Immagine Originale (Interattiva) ---
subplot(2, 2, 1);
hImgOrig = imshow(img);
title('📷 Immagine Originale (CLICCA PER CAMPIONARE)', 'FontSize', 11);
set(hImgOrig, 'ButtonDownFcn', @getPixelHSV);

% --- Canale V (Fondamentale per il Nero) ---
subplot(2, 2, 3);
imshow(imgHSV(:,:,3));
title('💡 Canale V (Luminosità - Utile per il Nero)', 'FontSize', 11);
colorbar;

% --- Maschera Risultante ---
subplot(1, 2, 2);
hMask = imshow(zeros(size(img, 1), size(img, 2)));
title('Maschera (Bianco = Rilevato)',
