#!/bin/bash

function ejecutar_diagnostico_so() {
    echo
    echo "STATUS CHECK"
    echo

    echo "Nombre del equipo: " 
    hostname
    echo
     
    echo "IP Actual: " 
    ip -4 addr show enp0s8 | grep inet | awk '{print $2}'
    echo

    echo "Espacio en disco: " 
    df -h /
}
