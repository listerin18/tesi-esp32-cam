%% MATLAB Controllo Robot ESP32-CAM con Line Following
clear; clc; close all;

% --- CONFIGURAZIONE ---
ipAddress = 'http://192.168.178.150'; 
optComandi = weboptions('Timeout', 0.4); % Timeout leggermente più basso per reattività

% Crea la figura
hFig = figure('Name', 'ESP32-CAM Controllo WASD + Line Following', 'NumberTitle', 'off', 'Position', [200, 100, 700, 650]);

% --- SLIDER POTENZA ---
uicontrol('Style', 'text', 'Position', [200 65 200 20], 'String', 'Potenza Motori (62 - 255)', 'FontWeight', 'bold');
hSlider = uicontrol('Style', 'slider', 'Min', 62, 'Max', 255, 'Value', 180, 'Position', [150 40 300 25]);

% ========== NUOVE FUNZIONALITÀ LINE FOLLOWING ==========

% --- PULSANTE LINE FOLLOWING ---
uicontrol('Style', 'pushbutton', ...
    'String', 'ATTIVA LINE FOLLOWING', ...
    'Position', [50 550 200 40], ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.8 0.2], ...
    'ForegroundColor', 'white', ...
    'Callback', @(~,~) attivaLineFollowing(ipAddress, optComandi));

% --- PULSANTE STOP LINE FOLLOWING ---
uicontrol('Style', 'pushbutton', ...
    'String', 'STOP', ...
    'Position', [270 550 100 40], ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.8 0.2 0.2], ...
    'ForegroundColor', 'white', ...
    'Callback', @(~,~) stopLineFollowing(ipAddress, optComandi));

% Pannello semplificato per Soglia Grigio
uicontrol('Style', 'text', 'Position', [400 535 150 20], 'String', 'Soglia Grigio (0-255):', 'FontWeight', 'bold');
hSoglia = uicontrol('Style', 'edit', 'Position', [560 535 50 25], 'String', '90');

uicontrol('Style', 'pushbutton', 'String', 'APPLICA SOGLIA', 'Position', [450 490 150 40], ...
    'FontWeight', 'bold', 'BackgroundColor', [0.2 0.6 0.8], 'ForegroundColor', 'white', ...
    'Callback', @(~,~) applicaSoglia(ipAddress, optComandi, hSoglia));



% ========== FINE NUOVE FUNZIONALITÀ ==========

fprintf('CONTROLLI ATTIVI:\n');
fprintf('- Tieni premuto WASD per muoverti\n');
fprintf('- Rilascia per fermarti\n');
fprintf('- Q per uscire\n');
fprintf('- Usa i pulsanti per Line Following\n\n');

% --- GESTIONE TASTI ---
set(hFig, 'KeyPressFcn', @(src, event) pressioneTasto(event, ipAddress, hSlider, optComandi));
set(hFig, 'KeyReleaseFcn', @(src, event) rilascioTasto(event, ipAddress, optComandi));

% --- LOOP PRINCIPALE (STREAM VIDEO) ---
% --- LOOP PRINCIPALE (STREAM VIDEO "A SCATTI VELOCI") ---
while ishandle(hFig)
    try
        % 1. Chiedi la singola foto all'indirizzo corretto
        img = imread([ipAddress, '/FOTO']);
        
        % 3. Aggiorna la visualizzazione
        imshow(img);
        title(['LIVE - Potenza: ', num2str(round(hSlider.Value)), ' - WASD per guidare']);
        
        % 4. Forza l'aggiornamento della finestra
        drawnow limitrate; 
    catch
        % Se un frame fallisce (es. lag wifi), non bloccare tutto
        pause(0.05); 
    end
end

% --- FUNZIONE: COSA SUCCEDE QUANDO PREMI ---
function pressioneTasto(event, ip, hSlider, opt)
    tasto = event.Key;
    v = round(hSlider.Value);
    comando = '';
    
    switch tasto
        case 'w', comando = ['/AVANTI?val=', num2str(v)];
        case 's', comando = ['/INDIETRO?val=', num2str(v)];
        case 'a', comando = ['/SINISTRA?val=', num2str(v)];
        case 'd', comando = ['/DESTRA?val=', num2str(v)];
        case 'q', close(gcf); return;
    end
    
    if ~isempty(comando)
        try
            webread([ip, comando], opt);
        catch
        end
    end
end

% --- FUNZIONE: COSA SUCCEDE QUANDO RILASCI ---
function rilascioTasto(event, ip, opt)
    tastiMovimento = {'w', 's', 'a', 'd'};
    % Se rilasci uno dei tasti di movimento, invia STOP
    if ismember(event.Key, tastiMovimento)
        try
            webread([ip, '/STOP'], opt);
            fprintf('Rilasciato: STOP\n');
        catch
        end
    end
end

% ========== NUOVE FUNZIONI LINE FOLLOWING ==========

% --- FUNZIONE: ATTIVA LINE FOLLOWING ---
function attivaLineFollowing(ip, opt)
    try
        webread([ip, '/LINEFOLLOW'], opt);
        fprintf('✓ LINE FOLLOWING ATTIVATO\n');
        msgbox('Line Following Attivato! Il robot seguirà la linea automaticamente.', 'Successo', 'help');
    catch err
        fprintf('✗ Errore attivazione: %s\n', err.message);
        errordlg('Impossibile attivare Line Following. Verifica la connessione.', 'Errore');
    end
end

% --- FUNZIONE: STOP LINE FOLLOWING ---
function stopLineFollowing(ip, opt)
    try
        webread([ip, '/STOP'], opt);
        fprintf('✓ LINE FOLLOWING FERMATO\n');
    catch err
        fprintf('✗ Errore stop: %s\n', err.message);
    end
end

function applicaSoglia(ip, opt, hSoglia)
    soglia = str2double(get(hSoglia, 'String'));
    
    if isnan(soglia) || soglia < 0 || soglia > 255
        errordlg('Inserisci un valore tra 0 e 255', 'Errore');
        return;
    end
    
    % Inviamo solo r2 che su Arduino viene letto come coloreSogliaMax
    comando = sprintf('/SETCOLOR?r2=%d', soglia);
    
    try
        webread([ip, comando], opt);
        fprintf('✓ Soglia Grigio impostata a: %d\n', soglia);
    catch err
        errordlg('Errore di connessione con il robot', 'Errore');
    end
end

% ========== FINE NUOVE FUNZIONI ==========


