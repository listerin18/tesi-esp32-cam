%% Sistema Line Following Autonomo - ESP32-CAM
% Questo script permette al robot di seguire autonomamente una linea colorata
% utilizzando elaborazione immagini in tempo reale

clear; clc; close all;

%% ========== CONFIGURAZIONE PARAMETRI ==========

% --- Connessione Robot ---
ipAddress = 'http://192.168.178.150';
optComandi = weboptions('Timeout', 0.5);

% --- Selezione Colore Linea ---
% Opzioni: 'rosso' o 'blu'
coloreScelto = 'rosso';

% --- Parametri HSV per Rilevamento Colore ---
if strcmp(coloreScelto, 'rosso')
    % Rosso: due range (0-10 e 170-180 in gradi, qui normalizzato 0-1)
    hsvMin1 = [0/180, 100/255, 100/255];      % H, S, V normalizzati
    hsvMax1 = [10/180, 1, 1];
    hsvMin2 = [170/180, 100/255, 100/255];    % Secondo range per rosso
    hsvMax2 = [1, 1, 1];
    usaDueRange = true;
    fprintf('Modalità: Rilevamento LINEA ROSSA\n');
elseif strcmp(coloreScelto, 'blu')
    hsvMin1 = [100/180, 100/255, 100/255];    % Blu
    hsvMax1 = [130/180, 1, 1];
    usaDueRange = false;
    fprintf('Modalità: Rilevamento LINEA BLU\n');
else % NERO
    hsvMin1 = [0, 0, 0];       % Qualsiasi colore, qualsiasi saturazione
    hsvMax1 = [1, 1, 0.35];    % Luminosità massima 35% (il "nero")
    usaDueRange = false;
    fprintf('Modalità: Rilevamento LINEA NERA\n');
end

% --- Parametri Controllo Motori ---
velocitaBase = 80;        % Velocità di crociera (80-220)
velocitaMinima = 60;       % Velocità minima motori
velocitaMassima = 120;     % Velocità massima motori

% --- Parametri Controllo Proporzionale ---
Kp = 0.8;                  % Guadagno proporzionale (0.5-1.5)
                           % Più alto = correzioni più aggressive

% --- Parametri Elaborazione Immagine ---
areaMinima = 500;          % Pixel minimi per considerare la linea valida
regioneInteresse = 0.6;    % Considera solo il 60% inferiore dell'immagine
                           % (la linea è davanti al robot)

% --- Parametri Visualizzazione ---
mostraDebug = true;        % Mostra visualizzazione debug
pauseTime = 0.05;          % Pausa tra frame (0.05 = ~20 FPS)

%% ========== INIZIALIZZAZIONE ==========

fprintf('\nConnessione a ESP32-CAM...\n');
fprintf('   IP: %s\n', ipAddress);

% Test connessione
try
    testImg = imread([ipAddress, '/jpg']);
    fprintf('Connessione stabilita!\n');
    fprintf('   Risoluzione: %dx%d pixel\n', size(testImg, 2), size(testImg, 1));
catch
    error('Impossibile connettersi al robot. Verifica IP e connessione WiFi.');
end

% Crea figura per visualizzazione
if mostraDebug
    hFig = figure('Name', 'Line Following Autonomo - ESP32-CAM', ...
                  'NumberTitle', 'off', ...
                  'Position', [100, 100, 900, 700]);
    
    % Subplot per immagine originale
    subplot(2, 2, 1);
    hImgOrig = imshow(testImg);
    title('Camera ESP32');
    
    % Subplot per maschera colore
    subplot(2, 2, 2);
    hImgMask = imshow(zeros(size(testImg, 1), size(testImg, 2)));
    title(['Maschera Colore: ', upper(coloreScelto)]);
    
    % Subplot per overlay
    subplot(2, 2, 3);
    hImgOverlay = imshow(testImg);
    title('Rilevamento Linea');
    
    % Subplot per info
    subplot(2, 2, 4);
    axis off;
    hText = text(0.1, 0.9, '', 'FontSize', 10, 'VerticalAlignment', 'top');
    title('Informazioni Sistema');
    
    fprintf('\nCONTROLLI:\n');
    fprintf('   - Premi Q per uscire\n');
    fprintf('   - Chiudi la finestra per fermare\n\n');
    
    % Gestione chiusura finestra
    set(hFig, 'CloseRequestFcn', @(src, event) chiudiFigura(src, ipAddress, optComandi));
    set(hFig, 'KeyPressFcn', @(src, event) gestisciTasto(event, hFig, ipAddress, optComandi));
end

fprintf('Avvio sistema autonomo...\n\n');

% Variabili per statistiche
frameCount = 0;
startTime = tic;
lineaPersa = 0;
maxLineaPersa = 10; % Ferma dopo 10 frame senza linea

%% ========== LOOP PRINCIPALE ==========

while ishandle(hFig)
    try
        frameCount = frameCount + 1;
        
        % --- 1. ACQUISIZIONE IMMAGINE ---
        img = imread([ipAddress, '/jpg']);
        img = imrotate(img, 180);  % Ruota se necessario
        
        [altezza, larghezza, ~] = size(img);
        
        % Considera solo la regione inferiore (dove si trova la linea)
        rigaInizio = round(altezza * (1 - regioneInteresse));
        imgROI = img(rigaInizio:end, :, :);
        
        % --- 2. CONVERSIONE HSV E RILEVAMENTO COLORE ---
        imgHSV = rgb2hsv(imgROI);
        
        % Crea maschera colore
        if usaDueRange
            % Per rosso: due range
            mask1 = (imgHSV(:,:,1) >= hsvMin1(1)) & (imgHSV(:,:,1) <= hsvMax1(1)) & ...
                    (imgHSV(:,:,2) >= hsvMin1(2)) & (imgHSV(:,:,3) >= hsvMin1(3));
            mask2 = (imgHSV(:,:,1) >= hsvMin2(1)) & (imgHSV(:,:,1) <= hsvMax2(1)) & ...
                    (imgHSV(:,:,2) >= hsvMin2(2)) & (imgHSV(:,:,3) >= hsvMin2(3));
            mask = mask1 | mask2;
        else
            % Per blu: un solo range
            mask = (imgHSV(:,:,1) >= hsvMin1(1)) & (imgHSV(:,:,1) <= hsvMax1(1)) & ...
                   (imgHSV(:,:,2) >= hsvMin1(2)) & (imgHSV(:,:,3) >= hsvMin1(3));
        end
        
        % Pulizia maschera (rimuovi rumore)
        mask = imopen(mask, strel('disk', 3));
        mask = imclose(mask, strel('disk', 5));
        
        % --- 3. CALCOLO CENTROIDE LINEA ---
        [y, x] = find(mask);
        areaLinea = length(x);
        
        if areaLinea > areaMinima
            % Linea trovata!
            lineaPersa = 0;
            
            % Calcola centroide
            centroX = mean(x);
            centroY = mean(y);
            
            % Calcola errore laterale (distanza dal centro immagine)
            centroImmagine = larghezza / 2;
            errore = centroX - centroImmagine;
            erroreNormalizzato = errore / (larghezza / 2); % -1 a +1
            
            % --- 4. CONTROLLO PROPORZIONALE ---
            correzione = Kp * errore;
            
            % Calcola velocità differenziale
            leftSpeed = velocitaBase - correzione;
            rightSpeed = velocitaBase + correzione;
            
            % Limita velocità nei range sicuri
            leftSpeed = max(velocitaMinima, min(velocitaMassima, leftSpeed));
            rightSpeed = max(velocitaMinima, min(velocitaMassima, rightSpeed));
            
            % --- 5. INVIA COMANDO AL ROBOT ---
            comando = sprintf('/DIFF?left=%d&right=%d', ...
                            round(leftSpeed), round(rightSpeed));
            webread([ipAddress, comando], optComandi);
            
            % Informazioni per debug
            direzione = 'DRITTO';
            if erroreNormalizzato < -0.1
                direzione = '← SINISTRA';
            elseif erroreNormalizzato > 0.1
                direzione = 'DESTRA →';
            end
            
            statoMsg = sprintf('LINEA RILEVATA\n');
            
        else
            % Linea NON trovata
            lineaPersa = lineaPersa + 1;
            
            if lineaPersa > maxLineaPersa
                % Ferma il robot
                webread([ipAddress, '/STOP'], optComandi);
                statoMsg = sprintf('LINEA PERSA - ROBOT FERMO\n');
                direzione = 'STOP';
                leftSpeed = 0;
                rightSpeed = 0;
                erroreNormalizzato = 0;
            else
                % Continua con ultimo comando
                statoMsg = sprintf('Ricerca linea... (%d/%d)\n', lineaPersa, maxLineaPersa);
                direzione = 'RICERCA';
                leftSpeed = velocitaBase;
                rightSpeed = velocitaBase;
                erroreNormalizzato = 0;
            end
            
            centroX = larghezza / 2;
            centroY = size(imgROI, 1) / 2;
        end
        
        % --- 6. VISUALIZZAZIONE DEBUG ---
        if mostraDebug && mod(frameCount, 2) == 0  % Aggiorna ogni 2 frame
            % Immagine originale
            set(hImgOrig, 'CData', img);
            
            % Maschera colore
            maskFull = zeros(altezza, larghezza);
            maskFull(rigaInizio:end, :) = mask;
            set(hImgMask, 'CData', maskFull);
            
            % Overlay con linea rilevata
            imgOverlay = img;
            if areaLinea > areaMinima
                % Disegna centroide
                centroXFull = centroX;
                centroYFull = centroY + rigaInizio;
                imgOverlay = insertMarker(imgOverlay, [centroXFull, centroYFull], ...
                                         'o', 'Color', 'red', 'Size', 15);
                imgOverlay = insertMarker(imgOverlay, [centroXFull, centroYFull], ...
                                         '+', 'Color', 'yellow', 'Size', 20);
                
                % Disegna linea centrale di riferimento
                imgOverlay = insertShape(imgOverlay, 'Line', ...
                                        [centroImmagine, 0, centroImmagine, altezza], ...
                                        'Color', 'green', 'LineWidth', 2);
                
                % Disegna vettore errore
                imgOverlay = insertShape(imgOverlay, 'Line', ...
                                        [centroImmagine, centroYFull, centroXFull, centroYFull], ...
                                        'Color', 'cyan', 'LineWidth', 3);
            end
            set(hImgOverlay, 'CData', imgOverlay);
            
            % Informazioni testuali
            fps = frameCount / toc(startTime);
            infoText = sprintf(['%s' ...
                               '━━━━━━━━━━━━━━━━━━━━\n' ...
                               'Direzione: %s\n' ...
                               'Errore: %.1f px (%.2f%%)\n' ...
                               'Motore SX: %d\n' ...
                               'Motore DX: %d\n' ...
                               'Area linea: %d px\n' ...
                               'FPS: %.1f\n' ...
                               'Frame: %d\n'], ...
                               statoMsg, direzione, errore, erroreNormalizzato*100, ...
                               round(leftSpeed), round(rightSpeed), ...
                               areaLinea, fps, frameCount);
            set(hText, 'String', infoText);
            
            drawnow limitrate;
        end
        
        % Pausa per controllo frame rate
        pause(pauseTime);
        
    catch ME
        fprintf('Errore nel loop: %s\n', ME.message);
        pause(0.1);
    end
end

% Cleanup finale
fprintf('\nSistema fermato.\n');
try
    webread([ipAddress, '/STOP'], optComandi);
    fprintf('Robot fermato correttamente.\n');
catch
    fprintf('Impossibile inviare comando STOP.\n');
end

%% ========== FUNZIONI HELPER ==========

function chiudiFigura(src, ip, opt)
    % Ferma il robot quando si chiude la finestra
    try
        webread([ip, '/STOP'], opt);
    catch
    end
    delete(src);
end

function gestisciTasto(event, fig, ip, opt)
    % Gestisce pressione tasti
    if strcmp(event.Key, 'q')
        try
            webread([ip, '/STOP'], opt);
        catch
        end
        close(fig);
    end
end


